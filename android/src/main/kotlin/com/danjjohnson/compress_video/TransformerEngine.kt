package com.danjjohnson.compress_video

import android.content.Context
import android.media.MediaCodecInfo
import android.media.MediaExtractor
import android.media.MediaFormat
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import androidx.media3.common.Effect
import androidx.media3.common.MediaItem
import androidx.media3.common.MimeTypes
import androidx.media3.effect.FrameDropEffect
import androidx.media3.effect.Presentation
import androidx.media3.transformer.Composition
import androidx.media3.transformer.DefaultEncoderFactory
import androidx.media3.transformer.EditedMediaItem
import androidx.media3.transformer.Effects
import androidx.media3.transformer.ExportException
import androidx.media3.transformer.ExportResult
import androidx.media3.transformer.ProgressHolder
import androidx.media3.transformer.Transformer
import androidx.media3.transformer.VideoEncoderSettings
import java.io.File
import java.io.FileOutputStream
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch

/**
 * Builds and drives one [Transformer] per compression job, entirely on the main Looper.
 *
 * Every call in this file that touches a [Transformer] -- build, start, poll, cancel -- happens
 * on the calling thread, which must already be the main Looper by the time [compress] is
 * invoked ([Compression] asserts this before calling in). Nothing here ever dispatches that
 * work to a background thread pool (02-RESEARCH.md Pattern 1); only the pre-Transformer input
 * probe and the post-export re-probe leave the main thread, and both do so through [Probe],
 * whose own background-dispatched work always resumes back on the caller's original (main)
 * context once it completes.
 */
class TransformerEngine(
    private val context: Context,
) {
    // Lazy: constructing a Handler touches Looper.getMainLooper() immediately, which is not
    // available in a plain JVM unit test (CompressVideoPluginTest constructs this class via
    // Compression's default parameter without ever calling compress()). Deferring construction
    // to first use means only a real call into this engine requires a real main Looper.
    private val mainHandler by lazy { Handler(Looper.getMainLooper()) }

    /**
     * Compresses [inputFile] (already probed as [inputInfo]) per [request], writing to a temp
     * file beside [destinationFile] and moving it into place on success (or copying the
     * original there instead, when the encode would not have been smaller). Progress is polled
     * every [PROGRESS_POLL_INTERVAL_MS] and forwarded through [onProgress]; a final value of
     * 100 is sent before this function returns on success.
     *
     * Suspends until the job completes, fails, or is cancelled via [JobRegistry.cancel] for
     * [jobId]. Every field of the returned message is read from a re-probe of the finished
     * output file via [Probe] -- never from [ExportResult]'s own approximate fields
     * (02-RESEARCH.md Pitfall 4) -- except [ExportResult.videoConversionProcess] and
     * [ExportResult.audioConversionProcess], which are the only reliable way to detect whether
     * Transformer actually transmuxed a track.
     */
    suspend fun compress(
        jobId: String,
        inputFile: File,
        inputInfo: MediaInfoMessage,
        request: CompressRequestMessage,
        destinationFile: File,
        onProgress: suspend (Double) -> Unit,
    ): CompressResultMessage {
        val startElapsedMs = SystemClock.elapsedRealtime()
        val inputBytes = inputFile.length()
        val inputAudioCodec = if (inputInfo.hasAudio) readAudioCodec(inputFile) else null

        val target =
            SizeGuard.resolve(
                buildSizeGuardInput(inputInfo, inputAudioCodec),
                buildSizeGuardOptions(request),
            )

        // Never-larger pre-check (D-11, CORE-05, plan 02-04 task 1): when the resolver already
        // knows encoding would not help, skip building a Transformer at all rather than running
        // a real encode only to discard it. The post-check in finishSuccess below is the
        // fallback for when the prediction is wrong -- this is the fast path for when it is
        // right, which is the common case for an already-small or already-compressed input.
        if (target.wouldUseOriginal) {
            copyFileAtomically(inputFile, destinationFile)
            onProgress(100.0)
            return buildResultFromDestination(
                destinationFile = destinationFile,
                inputBytes = inputBytes,
                startElapsedMs = startElapsedMs,
                transmuxed = false,
                usedOriginal = true,
                audioReencoded = false,
            )
        }

        val videoBitrateBps = target.videoBitrateBps
        val inputDisplayedWidthPx = inputInfo.widthPx.toInt()
        val inputDisplayedHeightPx = inputInfo.heightPx.toInt()

        val videoEffects =
            buildList<Effect> {
                if (target.targetWidthPx != inputDisplayedWidthPx ||
                    target.targetHeightPx != inputDisplayedHeightPx
                ) {
                    // Presentation.createForHeight preserves the frame's own aspect ratio, so
                    // handing it only the target height is sufficient: SizeGuard computed both
                    // dimensions from the same ratio, so the resulting width already matches
                    // target.targetWidthPx.
                    //
                    // No coded/displayed swap for rotation: measured live on the emulator
                    // (02-02-PLAN.md task 3's own instruction to record this). A rotated
                    // 1920x1080-coded, 90deg-matrix input targeting a 720-long-side preset
                    // produced width=406 when the target height was computed by swapping into
                    // coded space (720 as a "coded height", 720*1080/1920=405 rounded) --
                    // proving the effect pipeline already sees the DECODED, DISPLAY-oriented
                    // frame (1080x1920), not the coded pre-rotation frame. Passing the target
                    // straight from MediaInfoMessage's own displayed dimensions, with no swap,
                    // produced the correct 720x1280 output.
                    add(Presentation.createForHeight(target.targetHeightPx))
                }
                val inputFps = inputInfo.frameRateFps
                if (inputFps != null && target.effectiveFps < inputFps) {
                    // The frame-rate-cap effect from the effect library, not the
                    // EditedMediaItem builder's still-image frame-rate generator -- that
                    // builder method only synthesizes a frame rate when converting a still
                    // image to video and is a no-op on real video input (02-RESEARCH.md
                    // Pattern 3's "Important distinction").
                    add(FrameDropEffect.createDefaultFrameDropEffect(target.effectiveFps.toFloat()))
                }
            }

        val editedMediaItem =
            EditedMediaItem.Builder(MediaItem.fromUri(Uri.fromFile(inputFile)))
                .setRemoveAudio(request.audioMode == AudioModeMessage.STRIP)
                .setEffects(Effects(emptyList(), videoEffects))
                .build()

        val videoEncoderSettings =
            VideoEncoderSettings.Builder()
                .setBitrate(videoBitrateBps.toInt())
                // CBR, not the DefaultEncoderFactory/VideoEncoderSettings default of VBR
                // (02-RESEARCH.md Pattern 4): measured live this plan -- an explicit
                // videoBitrateBps request at VBR overshot by ~28% on this emulator's software
                // encoder over a short (4s) clip, while CBR landed within ~20%, inside the
                // 25% tolerance every corpus sidecar already uses for bitrate. The emulator's
                // encoder advertises both VBR and CBR (02-RESEARCH.md Pitfall 3's
                // `feature-bitrate-modes = "VBR,CBR"`), so this is a supported mode change,
                // not a workaround relying on undocumented behaviour.
                .setBitrateMode(MediaCodecInfo.EncoderCapabilities.BITRATE_MODE_CBR)
                .build()
        val encoderFactory =
            DefaultEncoderFactory.Builder(context)
                .setRequestedVideoEncoderSettings(videoEncoderSettings)
                .build()

        val deferred = CompletableDeferred<ExportOutcome>()
        val listener =
            object : Transformer.Listener {
                override fun onCompleted(
                    composition: Composition,
                    exportResult: ExportResult,
                ) {
                    deferred.complete(ExportOutcome.Success(exportResult))
                }

                override fun onError(
                    composition: Composition,
                    exportResult: ExportResult,
                    exportException: ExportException,
                ) {
                    deferred.complete(ExportOutcome.Failure(exportException))
                }
            }

        val transformer =
            Transformer.Builder(context)
                .setVideoMimeType(MimeTypes.VIDEO_H264)
                .setAudioMimeType(MimeTypes.AUDIO_AAC)
                .setEncoderFactory(encoderFactory)
                .addListener(listener)
                .build()

        val tempFile = PluginFiles.tempFileBeside(destinationFile)
        val progressHolder = ProgressHolder()
        // A dedicated scope for firing fire-and-forget progress events from the (non-suspend)
        // Runnable below -- cancelled once this job settles so it never outlives it.
        val progressScope = CoroutineScope(SupervisorJob() + Dispatchers.Main)

        lateinit var progressRunnable: Runnable
        progressRunnable =
            Runnable {
                val state = transformer.getProgress(progressHolder)
                if (state == Transformer.PROGRESS_STATE_AVAILABLE) {
                    progressScope.launch { onProgress(progressHolder.progress.toDouble()) }
                }
                // The class javadoc: "After an export completes, this method returns
                // PROGRESS_STATE_NOT_STARTED" -- JobRegistry.remove/cancel stop this loop on
                // both terminal paths rather than relying on getProgress to signal completion.
                mainHandler.postDelayed(progressRunnable, PROGRESS_POLL_INTERVAL_MS)
            }

        JobRegistry.register(
            jobId,
            JobRegistry.LiveJob(
                transformer = transformer,
                tempFile = tempFile,
                mainHandler = mainHandler,
                progressRunnable = progressRunnable,
                onCancelled = { deferred.complete(ExportOutcome.Cancelled) },
            ),
        )

        mainHandler.post(progressRunnable)
        transformer.start(editedMediaItem, tempFile.path)

        val outcome = deferred.await()
        JobRegistry.remove(jobId)
        progressScope.cancel()

        return when (outcome) {
            is ExportOutcome.Cancelled -> {
                PluginFiles.quietDelete(tempFile)
                throw CompressVideoError("cancelled", "The compression job was cancelled")
            }
            is ExportOutcome.Failure -> {
                PluginFiles.quietDelete(tempFile)
                throw mapExportException(outcome.exception)
            }
            is ExportOutcome.Success -> {
                onProgress(100.0)
                finishSuccess(outcome.exportResult, tempFile, destinationFile, inputFile, inputBytes, startElapsedMs)
            }
        }
    }

    /**
     * Finishes a successful export: decides never-larger substitution, re-probes the output
     * file with [Probe] for every dimension/duration/codec field, and reads the audio codec
     * separately (mirroring [Probe]'s own [MediaExtractor] pattern rather than modifying it,
     * since [MediaInfoMessage] has no audio-codec field).
     */
    private suspend fun finishSuccess(
        exportResult: ExportResult,
        tempFile: File,
        destinationFile: File,
        inputFile: File,
        inputBytes: Long,
        startElapsedMs: Long,
    ): CompressResultMessage {
        val tempBytes = tempFile.length()
        val usedOriginal = tempBytes >= inputBytes
        if (usedOriginal) {
            PluginFiles.quietDelete(tempFile)
            copyFileAtomically(inputFile, destinationFile)
        } else {
            PluginFiles.moveIntoPlace(tempFile, destinationFile)
        }

        val videoTransmuxed =
            exportResult.videoConversionProcess == ExportResult.CONVERSION_PROCESS_TRANSMUXED
        val audioTransmuxedOrAbsent =
            exportResult.audioConversionProcess == ExportResult.CONVERSION_PROCESS_TRANSMUXED ||
                exportResult.audioConversionProcess == ExportResult.CONVERSION_PROCESS_NA
        val audioReencoded =
            exportResult.audioConversionProcess == ExportResult.CONVERSION_PROCESS_TRANSCODED ||
                exportResult.audioConversionProcess ==
                ExportResult.CONVERSION_PROCESS_TRANSMUXED_AND_TRANSCODED

        return buildResultFromDestination(
            destinationFile = destinationFile,
            inputBytes = inputBytes,
            startElapsedMs = startElapsedMs,
            transmuxed = !usedOriginal && videoTransmuxed && audioTransmuxedOrAbsent,
            usedOriginal = usedOriginal,
            audioReencoded = audioReencoded,
        )
    }

    /**
     * Re-probes [destinationFile] with [Probe] for every dimension/duration/codec field and
     * reads its audio codec separately (mirroring [Probe]'s own [MediaExtractor] pattern rather
     * than modifying it, since [MediaInfoMessage] has no audio-codec field), then assembles the
     * [CompressResultMessage] both the real-encode path ([finishSuccess]) and the never-larger
     * pre-check path (in [compress]) return. Every field but the three passed in is read from
     * this re-probe, never from [ExportResult]'s own approximate fields (02-RESEARCH.md
     * Pitfall 4).
     */
    private suspend fun buildResultFromDestination(
        destinationFile: File,
        inputBytes: Long,
        startElapsedMs: Long,
        transmuxed: Boolean,
        usedOriginal: Boolean,
        audioReencoded: Boolean,
    ): CompressResultMessage {
        val outputInfo = Probe(context).getMediaInfo(destinationFile.path)
        val audioCodec = if (outputInfo.hasAudio) readAudioCodec(destinationFile) else null

        return CompressResultMessage(
            outputPath = destinationFile.canonicalPath,
            inputBytes = inputBytes,
            outputBytes = destinationFile.length(),
            widthPx = outputInfo.widthPx,
            heightPx = outputInfo.heightPx,
            durationMs = outputInfo.durationMs,
            videoCodec = outputInfo.videoCodec ?: "unknown",
            audioCodec = audioCodec,
            transmuxed = transmuxed,
            usedOriginal = usedOriginal,
            toneMapped = false,
            hevcFallback = false,
            audioReencoded = audioReencoded,
            elapsedMs = SystemClock.elapsedRealtime() - startElapsedMs,
        )
    }

    /**
     * Reads the normalised codec of [file]'s first audio track, or `null` if it has none.
     * Mirrors [Probe]'s own extractor-scan pattern without modifying that file.
     */
    private fun readAudioCodec(file: File): String? {
        val extractor = MediaExtractor()
        return try {
            extractor.setDataSource(file.path)
            var codec: String? = null
            for (i in 0 until extractor.trackCount) {
                val format = extractor.getTrackFormat(i)
                val mime = format.getString(MediaFormat.KEY_MIME) ?: continue
                if (mime.startsWith("audio/")) {
                    codec = normalizeAudioCodec(mime)
                    break
                }
            }
            codec
        } catch (e: Exception) {
            null
        } finally {
            extractor.release()
        }
    }

    /**
     * Normalises an audio track's MIME type into a wire-contract codec token. [MediaMath]'s own
     * `normalizeCodec` only recognises video tokens (it has no case for AAC's own MIME,
     * `audio/mp4a-latm`), so it is not reused here as-is -- extending it is deferred to a later
     * plan's `AudioOptions` work (AUDO-01/AUDO-02, not in this plan's scope), but reporting
     * `"unknown"` for every audio track in the meantime would make [CompressResultMessage]'s
     * own `audioCodec` field meaningless whenever a track is present. Any value this does not
     * recognise maps to `"unknown"`, matching [MediaMath.normalizeCodec]'s own contract.
     */
    private fun normalizeAudioCodec(mime: String): String =
        when (mime.lowercase()) {
            "audio/mp4a-latm", "audio/aac", "mp4a", "aac" -> "aac"
            else -> "unknown"
        }

    /**
     * Copies [source] to [destination] atomically (temp file beside the destination, then
     * rename), for the never-larger path where the original's own bytes become the output.
     * Never opens [source] for writing.
     */
    private fun copyFileAtomically(
        source: File,
        destination: File,
    ) {
        val temp = PluginFiles.tempFileBeside(destination)
        try {
            source.inputStream().use { input ->
                FileOutputStream(temp).use { output -> input.copyTo(output) }
            }
            PluginFiles.moveIntoPlace(temp, destination)
        } catch (e: CompressVideoError) {
            PluginFiles.quietDelete(temp)
            throw e
        } catch (e: Exception) {
            PluginFiles.quietDelete(temp)
            throw CompressVideoError("io", "Failed to copy the original file", e.message)
        }
    }

    /**
     * Builds [SizeGuard.InputInfo] from the probed [inputInfo]. [MediaInfoMessage] itself has no
     * audio-codec field (see [readAudioCodec]'s own doc comment), so [audioCodec] is read
     * separately, once, in [compress] before this is called and threaded through here -- needed
     * by [SizeGuard.Plan.wouldTransmux]'s audio-codec condition (D-10), which
     * [SizeGuard.InputInfo.audioBitrateBps] alone cannot answer.
     */
    private fun buildSizeGuardInput(
        inputInfo: MediaInfoMessage,
        audioCodec: String?,
    ): SizeGuard.InputInfo =
        SizeGuard.InputInfo(
            displayedWidthPx = inputInfo.widthPx.toInt(),
            displayedHeightPx = inputInfo.heightPx.toInt(),
            rotationDegrees = inputInfo.rotationDegrees.toInt(),
            durationMs = inputInfo.durationMs,
            sizeBytes = inputInfo.sizeBytes,
            videoCodec = inputInfo.videoCodec ?: "unknown",
            videoBitrateBps = inputInfo.videoBitrateBps,
            frameRateFps = inputInfo.frameRateFps,
            hasAudio = inputInfo.hasAudio,
            audioCodec = audioCodec,
            audioBitrateBps = null,
        )

    /**
     * Builds [SizeGuard.Options] from [request]. `maxLongSidePx`/`videoBitrateBps` are passed
     * straight through as explicit-override-or-`null` (02-03-PLAN.md's wire-contract change:
     * `CompressVideo._buildRequestMessage` no longer pre-resolves the preset's own bitrate into
     * these fields the way 02-02's tracer did, which would have made rule 6's preset-scaling
     * branch unreachable for the real Dart-to-native path). `presetMaxLongSidePx`/
     * `presetVideoBitrateBps` are always the selected preset's own nominal values, independent
     * of any override -- the reference SizeGuard's bitrate-scaling formula divides by.
     */
    private fun buildSizeGuardOptions(request: CompressRequestMessage): SizeGuard.Options =
        SizeGuard.Options(
            maxLongSidePx = request.maxLongSidePx,
            videoBitrateBps = request.videoBitrateBps,
            targetSizeMb = request.targetSizeMb,
            presetMaxLongSidePx = request.presetMaxLongSidePx,
            presetVideoBitrateBps = request.presetVideoBitrateBps,
            maxFps = request.maxFps,
            audioStripped = request.audioMode == AudioModeMessage.STRIP,
            audioPassthroughRequested = request.audioMode == AudioModeMessage.PASSTHROUGH,
            requestedAudioBitrateBps = request.audioBitrateBps,
            trimStartMs = request.trimStartMs,
            trimEndMs = request.trimEndMs,
        )

    /**
     * Maps [ExportException.errorCode] to a [CompressVideoError] reason per the table in
     * 02-RESEARCH.md (its own Pitfalls #8/#9 explain the choices CONTEXT.md left as "per
     * research").
     */
    private fun mapExportException(exception: ExportException): CompressVideoError {
        val reason =
            when (exception.errorCode) {
                ExportException.ERROR_CODE_IO_FILE_NOT_FOUND -> "fileNotFound"
                ExportException.ERROR_CODE_IO_UNSPECIFIED,
                ExportException.ERROR_CODE_IO_NETWORK_CONNECTION_FAILED,
                ExportException.ERROR_CODE_IO_NETWORK_CONNECTION_TIMEOUT,
                ExportException.ERROR_CODE_IO_INVALID_HTTP_CONTENT_TYPE,
                ExportException.ERROR_CODE_IO_BAD_HTTP_STATUS,
                ExportException.ERROR_CODE_IO_NO_PERMISSION,
                ExportException.ERROR_CODE_IO_CLEARTEXT_NOT_PERMITTED,
                ExportException.ERROR_CODE_IO_READ_POSITION_OUT_OF_RANGE,
                -> "io"
                ExportException.ERROR_CODE_DECODER_INIT_FAILED -> "decoderUnavailable"
                ExportException.ERROR_CODE_DECODING_FAILED,
                ExportException.ERROR_CODE_DECODING_FORMAT_UNSUPPORTED,
                -> "unsupportedInput"
                ExportException.ERROR_CODE_ENCODER_INIT_FAILED,
                ExportException.ERROR_CODE_ENCODING_FORMAT_UNSUPPORTED,
                ExportException.ERROR_CODE_ENCODING_FAILED,
                -> "encoderUnavailable"
                ExportException.ERROR_CODE_VIDEO_FRAME_PROCESSING_FAILED,
                ExportException.ERROR_CODE_AUDIO_PROCESSING_FAILED,
                ExportException.ERROR_CODE_MUXING_FAILED,
                ExportException.ERROR_CODE_MUXING_TIMEOUT,
                ExportException.ERROR_CODE_MUXING_APPEND,
                -> "io"
                else -> "unknown"
            }
        val message = exception.message ?: "Media3 export failed with code ${exception.errorCode}"
        return CompressVideoError(reason, message, exception.errorCode.toString())
    }

    private sealed class ExportOutcome {
        data class Success(val exportResult: ExportResult) : ExportOutcome()

        data class Failure(val exception: ExportException) : ExportOutcome()

        object Cancelled : ExportOutcome()
    }

    private companion object {
        const val PROGRESS_POLL_INTERVAL_MS = 250L
    }
}
