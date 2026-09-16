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
import androidx.media3.common.audio.AudioProcessor
import androidx.media3.common.audio.ChannelMixingAudioProcessor
import androidx.media3.common.audio.ChannelMixingMatrix
import androidx.media3.effect.FrameDropEffect
import androidx.media3.effect.Presentation
import androidx.media3.transformer.AudioEncoderSettings
import androidx.media3.transformer.Composition
import androidx.media3.transformer.DefaultEncoderFactory
import androidx.media3.transformer.EditedMediaItem
import androidx.media3.transformer.Effects
import androidx.media3.transformer.ExportException
import androidx.media3.transformer.ExportResult
import androidx.media3.transformer.InAppMp4Muxer
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
        val inputAudioChannels = if (inputInfo.hasAudio) readAudioChannelCount(inputFile) else null

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
            buildVideoEffects(
                target = target,
                inputDisplayedWidthPx = inputDisplayedWidthPx,
                inputDisplayedHeightPx = inputDisplayedHeightPx,
                inputFps = inputInfo.frameRateFps,
            )

        // Channel-count changes go through the platform's own mixing processor
        // (ChannelMixingAudioProcessor + ChannelMixingMatrix.createForConstantGain), never
        // hand-written per-sample downmix math (02-RESEARCH.md Pattern 5, Don't Hand-Roll):
        // AudioEncoderSettings has no channel-count field of its own to set. Only meaningful --
        // and only added -- for an explicit re-encode with a target channel count that differs
        // from what the source actually has; passthrough and strip never touch this list, for
        // the same "leave the audio pipeline alone unless asked to change it" reason the
        // encoder-factory branch below leaves audio encoder settings at their Media3 default
        // for anything other than a forced re-encode.
        val requestedAudioChannels = request.audioChannels?.toInt()
        val audioProcessors: List<AudioProcessor> =
            if (request.audioMode == AudioModeMessage.REENCODE &&
                requestedAudioChannels != null &&
                inputAudioChannels != null &&
                requestedAudioChannels != inputAudioChannels
            ) {
                listOf(
                    ChannelMixingAudioProcessor().apply {
                        putChannelMixingMatrix(
                            ChannelMixingMatrix.createForConstantGain(
                                inputAudioChannels,
                                requestedAudioChannels,
                            ),
                        )
                    },
                )
            } else {
                emptyList()
            }

        // Trim: Media3's own MediaItem.ClippingConfiguration, never hand-rolled range maths
        // (D-16). setEndPositionMs takes an END POSITION, not a duration -- the incumbent's own
        // Android trim bug (02-05-PLAN.md task 2) came from passing a duration where the
        // library wanted an end position. Both positions are taken straight from the request in
        // milliseconds with this one conversion at the boundary; a `null` trimStartMs/trimEndMs
        // defaults to the start/end of the input, matching SizeGuard's own rule 6/7 fallback.
        val mediaItemBuilder = MediaItem.Builder().setUri(Uri.fromFile(inputFile))
        if (request.trimStartMs != null || request.trimEndMs != null) {
            mediaItemBuilder.setClippingConfiguration(
                MediaItem.ClippingConfiguration.Builder()
                    .setStartPositionMs(request.trimStartMs ?: 0L)
                    .setEndPositionMs(request.trimEndMs ?: inputInfo.durationMs)
                    .build(),
            )
        }

        val editedMediaItem =
            EditedMediaItem.Builder(mediaItemBuilder.build())
                .setRemoveAudio(request.audioMode == AudioModeMessage.STRIP)
                .setEffects(Effects(audioProcessors, videoEffects))
                .build()

        // DefaultEncoderFactory.videoNeedsEncoding() returns true whenever
        // requestedVideoEncoderSettings != VideoEncoderSettings.DEFAULT -- read live from the
        // installed media3-transformer AAR this plan (javap on DefaultEncoderFactory.class),
        // since neither the public Javadoc nor 02-RESEARCH.md's Pattern 2 documents it. Every
        // encode path before this plan always built a non-default VideoEncoderSettings, which
        // meant TransformerUtil.shouldTranscodeVideo's very first bespoke check
        // (`encoderFactory.videoNeedsEncoding()`) short-circuited to `true` before it ever
        // reached the mime-type/effects comparison that would have let a qualifying clip
        // transmux -- the fast path was unreachable code until this fix, regardless of what
        // SizeGuard predicted. A remux must therefore leave the video encoder settings at
        // [VideoEncoderSettings.DEFAULT] (no [DefaultEncoderFactory.Builder.setRequestedVideoEncoderSettings]
        // call at all), which is also why no bitrate is requested on this branch -- a remux
        // copies the input's own bitrate, it does not target one.
        //
        // Audio encoder settings follow exactly the same rule (`DefaultEncoderFactory.
        // audioNeedsEncoding()` -- confirmed by the same javap read this plan -- returns true
        // whenever `requestedAudioEncoderSettings != AudioEncoderSettings.DEFAULT`, using plain
        // reference/Object equality since AudioEncoderSettings has no `equals()` override, so
        // even a structurally-default-looking built settings object would still force a
        // transcode): they are only ever set below for an explicit `REENCODE` request, never for
        // passthrough or strip, so an already-AAC passthrough track can still be transmuxed
        // rather than needlessly re-encoded. `wouldTransmux` is already false for any REENCODE
        // or STRIP request (SizeGuard's audioPassthroughRequested condition), so this branch is
        // always the "not transmuxing" branch in that case, and it is safe to add audio encoder
        // settings here without risking the transmux fast path.
        val encoderFactory =
            if (target.wouldTransmux) {
                DefaultEncoderFactory.Builder(context).build()
            } else {
                val videoEncoderSettings =
                    VideoEncoderSettings.Builder()
                        .setBitrate(videoBitrateBps.toInt())
                        // CBR, not the DefaultEncoderFactory/VideoEncoderSettings default of
                        // VBR (02-RESEARCH.md Pattern 4): measured live this plan -- an
                        // explicit videoBitrateBps request at VBR overshot by ~28% on this
                        // emulator's software encoder over a short (4s) clip, while CBR landed
                        // within ~20%, inside the 25% tolerance every corpus sidecar already
                        // uses for bitrate. The emulator's encoder advertises both VBR and CBR
                        // (02-RESEARCH.md Pitfall 3's `feature-bitrate-modes = "VBR,CBR"`), so
                        // this is a supported mode change, not a workaround relying on
                        // undocumented behaviour.
                        .setBitrateMode(MediaCodecInfo.EncoderCapabilities.BITRATE_MODE_CBR)
                        .build()
                val builder =
                    DefaultEncoderFactory.Builder(context)
                        .setRequestedVideoEncoderSettings(videoEncoderSettings)
                if (request.audioMode == AudioModeMessage.REENCODE) {
                    // target.audioBitrateBps is SizeGuard rule 5's already-clamped resolution
                    // (8,000-960,000bps, request-or-source-or-default) -- this branch trusts it
                    // rather than re-deriving or re-clamping the request's own raw bitrate.
                    builder.setRequestedAudioEncoderSettings(
                        AudioEncoderSettings.Builder()
                            .setBitrate(target.audioBitrateBps.toInt())
                            .build(),
                    )
                }
                builder.build()
            }

        val deferred = CompletableDeferred<ExportOutcome>()
        val listener =
            object : Transformer.Listener {
                override fun onCompleted(
                    composition: Composition,
                    exportResult: ExportResult,
                ) {
                    // Stop polling HERE, inside the terminal callback itself, rather than
                    // waiting for JobRegistry.remove after this suspend function resumes: the
                    // Transformer class javadoc states getProgress reports
                    // PROGRESS_STATE_NOT_STARTED once an export completes, so the polling loop
                    // must stop itself proactively rather than rely on that state change.
                    JobRegistry.stopPolling(jobId)
                    deferred.complete(ExportOutcome.Success(exportResult))
                }

                override fun onError(
                    composition: Composition,
                    exportResult: ExportResult,
                    exportException: ExportException,
                ) {
                    JobRegistry.stopPolling(jobId)
                    deferred.complete(ExportOutcome.Failure(exportException))
                }
            }

        // No composition-level transmux flags (Transformer.Builder has no such API; the
        // per-EditedMediaItem knobs 02-RESEARCH.md Pattern 2 names are ignored for a
        // single-item composition, so there is no reachable code path here where setting them
        // would do anything). When target.wouldTransmux is true, videoEffects above is already
        // empty and requesting H.264/AAC output already matches the input's own codecs (the
        // predicate requires exactly that), so Media3's own "transcode only if necessary"
        // behaviour transmuxes both tracks without any extra wiring on this builder.
        //
        // setAudioMimeType(AUDIO_AAC) is unconditional, for every audio mode -- deliberately not
        // branched the way the encoder-factory settings above are. It is what makes AUDO-01's
        // default path safe: when the source audio is already AAC, requesting AAC output simply
        // matches (no forced transcode, confirmed by the passing small_480p.mp4 transmux case
        // below), so passthrough still copies; when the source audio is present but NOT AAC,
        // this same unconditional request is what makes Media3 transcode it to AAC rather than
        // failing outright or trying to mux an incompatible codec into the output MP4 (D-14) --
        // there is deliberately no separate "is this AAC" branch here because the one
        // unconditional call already covers both outcomes.
        //
        // Explicit InAppMp4Muxer.Factory with streamable output DISABLED -- found and fixed
        // this plan (Rule 1 bug, orchestrator-flagged): Transformer.Builder's own default
        // muxer (DefaultMuxer.Factory, confirmed via javap on the installed
        // media3-transformer:1.11.1 AAR) already delegates to InAppMp4Muxer with
        // attemptStreamableOutputEnabled left at ITS OWN default of true. That default writes
        // moov before mdat (so playback can start before the file finishes downloading) by
        // reserving a speculative `free` box after moov sized for moov to grow into as samples
        // arrive, then leaves whatever is unused as a real `free` box in the final file. For a
        // short, few-sample clip that reservation dwarfs the actual content: a raw MP4-box walk
        // of a remuxed small_480p.mp4 (77,504 input bytes) found a single 395,344-byte `free`
        // box -- the entire cause of a measured 472,825-byte "remux" of a 77KB clip, not muxer
        // overhead in any normal sense. Disabling streamable output removes that reservation
        // entirely (the same remux then measures 77,481 bytes, smaller than the input) at the
        // cost of moov landing at the end of the file instead of the start; this plugin's output
        // is written to local storage for the caller to read as a whole file, not progressively
        // streamed while still being written, so that cost is not a real one here.
        val transformer =
            Transformer.Builder(context)
                .setVideoMimeType(MimeTypes.VIDEO_H264)
                .setAudioMimeType(MimeTypes.AUDIO_AAC)
                .setEncoderFactory(encoderFactory)
                .setMuxerFactory(InAppMp4Muxer.Factory().setAttemptStreamableOutputEnabled(false))
                .addListener(listener)
                .build()

        val tempFile = PluginFiles.tempFileBeside(destinationFile)
        val progressHolder = ProgressHolder()
        // A dedicated scope for firing fire-and-forget progress events from the (non-suspend)
        // Runnable below -- cancelled once this job settles so it never outlives it.
        val progressScope = CoroutineScope(SupervisorJob() + Dispatchers.Main)

        // Remembers the last value actually forwarded for THIS job -- a fresh 0.0 per call to
        // [compress], since this variable lives in this function's own local scope alongside
        // the rest of this job's state, so two jobs polling concurrently can never see or
        // affect each other's last-sent value.
        var lastSentProgress = 0.0
        lateinit var progressRunnable: Runnable
        progressRunnable =
            Runnable {
                val state = transformer.getProgress(progressHolder)
                if (state == Transformer.PROGRESS_STATE_AVAILABLE) {
                    // Clamp into 0..99, not 0..100: measured live this task -- the exporter can
                    // report PROGRESS_STATE_AVAILABLE with progress already at 100 for several
                    // poll ticks BEFORE onCompleted actually fires (muxing/finalisation happens
                    // after the reported progress reaches its own ceiling), which would forward
                    // 100 multiple times if this loop's own upper clamp allowed it through. The
                    // single canonical terminal 100 is reserved for the explicit onProgress(100.0)
                    // call made once, right before the success/never-larger/remux-shortcut reply
                    // below -- this is what guarantees 100 appears exactly once in the whole
                    // stream, per 02-06-PLAN.md task 1's acceptance criteria. Never forward a
                    // value smaller than the last one actually sent for this job, either --
                    // monotonically non-decreasing.
                    val clamped = progressHolder.progress.toDouble().coerceIn(0.0, 99.0)
                    val forwarded = maxOf(clamped, lastSentProgress)
                    lastSentProgress = forwarded
                    progressScope.launch { onProgress(forwarded) }
                }
                // The class javadoc: "After an export completes, this method returns
                // PROGRESS_STATE_NOT_STARTED" -- the terminal Transformer.Listener callbacks
                // above call JobRegistry.stopPolling the instant they fire (rather than relying
                // on this state change, or on JobRegistry.remove/cancel after this suspend
                // function resumes) to stop this loop on every terminal path.
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
     * Finishes a successful export: runs the never-larger POST-check on the real byte count on
     * disk (the pre-check in [compress] is a heuristic; this is the fact) -- UNCONDITIONALLY,
     * on every produced file, remux or real encode alike -- then, only for a file that survives
     * that check, detects transmux from [exportResult]'s own per-track conversion-process
     * fields rather than from the prediction, and builds the final result via
     * [buildResultFromDestination].
     *
     * CORE-05 ("never makes the file bigger") describes the file the caller receives, not the
     * code path that produced it: a caller who gets a bigger file has been harmed exactly the
     * same amount whether that file came from an encode or a remux. "Transmux is decided first,
     * never-larger second" (02-04-PLAN.md's decision order) governs which Media3 operation
     * [compress] *attempts* -- it is not a license to skip re-verifying the result the same way
     * every other path does. A discarded remux is reported [CompressResultMessage.transmuxed]
     * `false`: the file the caller actually receives (a copy of the original) was not
     * transmuxed, whatever Media3's own internal conversion-process fields say about the
     * (discarded) temp file.
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

        // Detected from the export result's own per-track conversion-process fields rather than
        // from the prediction -- the prediction is a plan, the export result is the record --
        // but only when usedOriginal is false: the returned file must describe itself, and a
        // substituted original was never transmuxed or re-encoded, regardless of what Media3
        // did to the temp file this job discarded.
        val videoTransmuxed =
            exportResult.videoConversionProcess == ExportResult.CONVERSION_PROCESS_TRANSMUXED
        val audioTransmuxedOrAbsent =
            exportResult.audioConversionProcess == ExportResult.CONVERSION_PROCESS_TRANSMUXED ||
                exportResult.audioConversionProcess == ExportResult.CONVERSION_PROCESS_NA
        val transmuxed = !usedOriginal && videoTransmuxed && audioTransmuxedOrAbsent
        val audioReencoded =
            !usedOriginal &&
                (
                    exportResult.audioConversionProcess ==
                        ExportResult.CONVERSION_PROCESS_TRANSCODED ||
                        exportResult.audioConversionProcess ==
                        ExportResult.CONVERSION_PROCESS_TRANSMUXED_AND_TRANSCODED
                )

        return buildResultFromDestination(
            destinationFile = destinationFile,
            inputBytes = inputBytes,
            startElapsedMs = startElapsedMs,
            transmuxed = transmuxed,
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
     * Reads the channel count of [file]'s first audio track, or `null` if it has none or the
     * platform could not determine it. This is native-only information -- [MediaInfoMessage] has
     * no channel-count field of its own to cross the wire, since the only place it is needed is
     * here, to decide whether [compress]'s re-encode branch must add a
     * [ChannelMixingAudioProcessor] at all (AUDO-02's "channels" only ever changes what the
     * encoder is asked to produce, never what the caller is told about the source).
     */
    private fun readAudioChannelCount(file: File): Int? {
        val extractor = MediaExtractor()
        return try {
            extractor.setDataSource(file.path)
            var channels: Int? = null
            for (i in 0 until extractor.trackCount) {
                val format = extractor.getTrackFormat(i)
                val mime = format.getString(MediaFormat.KEY_MIME) ?: continue
                if (mime.startsWith("audio/") && format.containsKey(MediaFormat.KEY_CHANNEL_COUNT)) {
                    channels = format.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
                    break
                }
            }
            channels
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

    internal companion object {
        private const val PROGRESS_POLL_INTERVAL_MS = 250L

        /**
         * Builds the video effects list in one fixed, documented order: geometry
         * ([Presentation], the resize) first, then frame selection ([FrameDropEffect], the fps
         * cap). The two are independent today -- resizing doesn't change which frames are kept,
         * and dropping frames doesn't change their size -- but the order is pinned here, once,
         * so a future edit to either one cannot silently reorder them. [EffectOrderTest]
         * exercises this function directly and constructs no [Transformer].
         *
         * Pure: no [Context], no Looper, no Transformer -- callable from a plain JVM unit test
         * exactly like [SizeGuard.resolve].
         */
        internal fun buildVideoEffects(
            target: SizeGuard.Plan,
            inputDisplayedWidthPx: Int,
            inputDisplayedHeightPx: Int,
            inputFps: Double?,
        ): List<Effect> =
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
                if (inputFps != null && target.effectiveFps < inputFps) {
                    // The frame-rate-cap effect from the effect library, not the
                    // EditedMediaItem builder's still-image frame-rate generator -- that
                    // builder method only synthesizes a frame rate when converting a still
                    // image to video and is a no-op on real video input (02-RESEARCH.md
                    // Pattern 3's "Important distinction").
                    add(FrameDropEffect.createDefaultFrameDropEffect(target.effectiveFps.toFloat()))
                }
            }
    }
}
