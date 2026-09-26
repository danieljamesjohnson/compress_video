package com.danjjohnson.compress_video

import android.content.Context
import android.media.MediaCodecInfo
import android.media.MediaExtractor
import android.media.MediaFormat
import android.media.MediaMetadataRetriever
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import androidx.media3.common.C
import androidx.media3.common.ColorInfo
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
import androidx.media3.transformer.EditedMediaItemSequence
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
import kotlinx.coroutines.withContext

/**
 * Builds and drives one [Transformer] per compression job, entirely on the main Looper.
 *
 * Every call in this file that touches a [Transformer] -- build, start, poll, cancel -- happens
 * on the calling thread, which must already be the main Looper by the time [compress] is
 * invoked ([Compression] asserts this before calling in). The [Transformer] itself is never
 * built, started, polled or cancelled off that thread (02-RESEARCH.md Pattern 1); everything
 * else that can block on I/O -- the pre-Transformer input probe, the post-export re-probe, the
 * never-larger byte copy ([copyFileAtomically], CR-01), and the ancillary [MediaExtractor]
 * metadata reads ([readAudioCodec], [readAudioChannelCount], WR-04) -- dispatches to
 * [Dispatchers.IO] and always resumes back on the caller's original (main) context once it
 * completes, the same pattern [Probe] already uses for its own blocking native calls.
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

        val target = resolvePlan(inputFile, inputInfo, request)

        // HEVC opt-in (CDEC-01) and keep-HDR (CDEC-03) capability gates, computed once, up
        // front, independent of whether an encode ever runs and independent of each other's
        // OWN success -- both feed into the SAME outputIsHevc decision below (04-RESEARCH.md
        // Pattern 4 -- Media3's own automatic HdrMode step-down changes only the HDR mode,
        // never the requested video MIME type, so this probe -- not that step-down -- is what
        // decides H.264-vs-HEVC output). hasHardwareHevcEncoder()/resolveKeepHdrAchievable() are
        // the SAME functions resolvePlan calls (via buildSizeGuardOptions) to resolve
        // SizeGuard.Options.outputCodecIsHevc, so this job and estimate() can never disagree
        // about which codec would really be produced (02-07's own estimate()/compress()
        // agreement invariant).
        val requestedHevc = request.videoCodec == "hevc"
        val requestedKeepHdr = request.hdrMode == "keepHdr"
        val hasHardwareHevc = requestedHevc && hasHardwareHevcEncoder()
        val keepHdrAchievable =
            resolveKeepHdrAchievable(inputFile, inputInfo.isHdr, requestedKeepHdr)
        val outputIsHevc = hasHardwareHevc || keepHdrAchievable
        val resolvedVideoMimeType = if (outputIsHevc) MimeTypes.VIDEO_H265 else MimeTypes.VIDEO_H264

        // D-06/D-08: true when the caller asked for HEVC and this device has no hardware HEVC
        // encoder, OR asked for keep-HDR and keep-HDR is not achievable -- a keep-HDR request
        // that comes back with toneMapped:true is how a caller learns the fallback happened.
        // Threaded as a real parameter now, all the way through finishSuccess into
        // buildResultFromDestination, guarded there by the same !usedOriginal check
        // toneMapped/transmuxed/audioReencoded already use: a substituted original or a skipped
        // encode never "fell back" to anything, whatever this raw value says.
        val hevcFallback =
            (requestedHevc && !hasHardwareHevc) || (requestedKeepHdr && !keepHdrAchievable)

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
                // No Transformer ever runs on this fast path -- nothing could have been
                // tone-mapped or have fallen back to anything. finishSuccess's own !usedOriginal
                // guard would compute the same answer for both flags, but there is no
                // ExportResult here to compute it from.
                toneMapped = NO_TRANSFORM_ATTEMPTED,
                hevcFallback = NO_TRANSFORM_ATTEMPTED,
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

        // AUDO-03 forced re-encode (04-RESEARCH.md Pitfall 1): a real, previously-undocumented
        // gap -- today, ONLY an explicit REENCODE request builds a ChannelMixingAudioProcessor
        // or explicit AudioEncoderSettings. A 5.1 AAC source, or any non-AAC source, under the
        // DEFAULT AudioPassthrough option would sail straight through untouched: not what
        // "compress with default options" needs to produce (stereo AAC, audioReencoded: true).
        // Computed once, here, before the processors and the encoder factory are built: forced
        // whenever the request is not already an explicit re-encode or a strip (there is
        // nothing to force onto a track already being re-encoded or removed), the input has
        // audio, and either its normalised codec is not AAC or its channel count exceeds
        // stereo.
        val audioForcedReencode =
            request.audioMode != AudioModeMessage.REENCODE &&
                request.audioMode != AudioModeMessage.STRIP &&
                inputInfo.hasAudio &&
                (
                    inputAudioCodec != AUDIO_CODEC_AAC_TOKEN ||
                        (inputAudioChannels != null && inputAudioChannels > FORCED_AUDIO_REENCODE_MAX_CHANNELS)
                )

        // Channel-count changes go through the platform's own mixing processor
        // (ChannelMixingAudioProcessor + ChannelMixingMatrix.createForConstantGain), never
        // hand-written per-sample downmix math (02-RESEARCH.md Pattern 5, Don't Hand-Roll):
        // AudioEncoderSettings has no channel-count field of its own to set. Only meaningful --
        // and only added -- when the target channel count differs from what the source actually
        // has; passthrough (with nothing forcing it) and strip never touch this list, for the
        // same "leave the audio pipeline alone unless asked to change it" reason the
        // encoder-factory branch below leaves audio encoder settings at their Media3 default
        // for anything other than a re-encode.
        val requestedAudioChannels = request.audioChannels?.toInt()
        val targetAudioChannels =
            when {
                request.audioMode == AudioModeMessage.REENCODE -> requestedAudioChannels
                // Capped at 2, never upmixed: a mono non-AAC source targets its own 1 channel,
                // a stereo or 5.1+ source targets 2. An unreadable source channel count on a
                // path already forcing a re-encode falls back to this plugin's own 2-channel
                // default rather than leaving the mixing matrix undecided.
                audioForcedReencode -> (inputAudioChannels ?: FORCED_AUDIO_REENCODE_MAX_CHANNELS)
                    .coerceAtMost(FORCED_AUDIO_REENCODE_MAX_CHANNELS)
                else -> null
            }
        val audioProcessors: List<AudioProcessor> =
            if (targetAudioChannels != null &&
                inputAudioChannels != null &&
                targetAudioChannels != inputAudioChannels
            ) {
                listOf(
                    ChannelMixingAudioProcessor().apply {
                        putChannelMixingMatrix(
                            channelMixingMatrixFor(inputAudioChannels, targetAudioChannels),
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
                } else if (audioForcedReencode) {
                    // The source's own audio bitrate (what SizeGuard rule 5 would otherwise
                    // resolve) describes six channels or raw LPCM here -- the wrong number to
                    // ask a 1-or-2-channel AAC encoder for. A fixed, named constant instead
                    // (AUDO-03, 04-RESEARCH.md Pitfall 1) -- this is what actually makes Media3
                    // transcode the track rather than copy it; the ChannelMixingAudioProcessor
                    // above alone only changes what samples the encoder receives, not whether
                    // Media3 decides an encode is needed at all.
                    builder.setRequestedAudioEncoderSettings(
                        AudioEncoderSettings.Builder()
                            .setBitrate(FORCED_AUDIO_REENCODE_BITRATE_BPS)
                            .build(),
                    )
                }
                builder.build()
            }

        // Whether this job's tone-map decision might need the OpenGL->MediaCodec fallback chain
        // at all (04-RESEARCH.md Pattern 2/Pitfall 3): true for a genuinely HDR source whenever
        // keep-HDR is not achievable -- which covers both the default toneMapToSdr request AND a
        // keepHdr request this device cannot honour (D-08's fallback is tone-mapped SDR H.264,
        // via the same chain). A non-HDR job, or an HDR job whose keep-HDR IS achievable, never
        // attempts the retry and never sees the exhausted-chain error message below.
        val isHdrToneMapAttempt = inputInfo.isHdr && !keepHdrAchievable

        // Shared across every attempt of THIS job (never reset to 0.0 on a retry): the poller
        // below already refuses to forward a value smaller than the last one actually sent, so a
        // second attempt's own progress restarting at 0 produces a pause in what the caller sees,
        // never a rewind (04-02-PLAN.md task 2). Declared here, once, rather than inside
        // [attemptExport], precisely so a retry's fresh [ProgressHolder] does not reset it.
        var lastSentProgress = 0.0

        // Performs ONE export attempt at [hdrMode]: builds its own [Transformer] and its own temp
        // file via [PluginFiles.tempFileBeside], registers with [JobRegistry], starts, awaits the
        // outcome and returns it alongside the temp file it wrote to. Neither a [Transformer] nor
        // a temp file is reused across attempts (04-RESEARCH.md Pattern 2/Anti-Patterns): each
        // call here builds fresh instances of both. A local suspend function, not a member one,
        // so it can close over every value already resolved above ([editedMediaItem],
        // [encoderFactory], [jobId], [destinationFile], [onProgress], [mainHandler] and the
        // shared [lastSentProgress]) without a long parameter list or a separate mutable-ref type.
        suspend fun attemptExport(hdrMode: Int): Pair<ExportOutcome, File> {
            val attemptDeferred = CompletableDeferred<ExportOutcome>()
            val listener =
                object : Transformer.Listener {
                    override fun onCompleted(
                        composition: Composition,
                        exportResult: ExportResult,
                    ) {
                        // Stop polling HERE, inside the terminal callback itself, rather than
                        // waiting for JobRegistry.remove after this suspend function resumes: the
                        // Transformer class javadoc states getProgress reports
                        // PROGRESS_STATE_NOT_STARTED once an export completes, so the polling
                        // loop must stop itself proactively rather than rely on that state
                        // change.
                        JobRegistry.stopPolling(jobId)
                        attemptDeferred.complete(ExportOutcome.Success(exportResult))
                    }

                    override fun onError(
                        composition: Composition,
                        exportResult: ExportResult,
                        exportException: ExportException,
                    ) {
                        JobRegistry.stopPolling(jobId)
                        attemptDeferred.complete(ExportOutcome.Failure(exportException))
                    }
                }

            // Every export starts through the Composition overload, unconditionally, rather than
            // branching between start(EditedMediaItem, ...) and start(Composition, ...): a
            // Composition wrapping a single item changes nothing for a non-HDR clip, so one code
            // path is worth more than a micro-optimisation for the common case (04-RESEARCH.md
            // Pattern 1). This is also the only way to set HdrMode at all -- it lives on
            // Composition.Builder, with no equivalent on the EditedMediaItem overload.
            val sequence = EditedMediaItemSequence.Builder(editedMediaItem).build()
            val composition = Composition.Builder(sequence).setHdrMode(hdrMode).build()

            // No composition-level transmux flags (Transformer.Builder has no such API; the
            // per-EditedMediaItem knobs 02-RESEARCH.md Pattern 2 names are ignored for a
            // single-item composition, so there is no reachable code path here where setting
            // them would do anything). When target.wouldTransmux is true, videoEffects above is
            // already empty and resolvedVideoMimeType is guaranteed H.264 (04-03,
            // SizeGuard.Options.outputCodecIsHevc disqualifies transmux for any request that
            // would really resolve to HEVC output), matching the input's own codecs (the
            // predicate requires exactly that) so Media3's own "transcode only if necessary"
            // behaviour transmuxes both tracks without any extra wiring on this builder.
            //
            // setAudioMimeType(AUDIO_AAC) is unconditional, for every audio mode -- deliberately
            // not branched the way the encoder-factory settings above are. It is what makes
            // AUDO-01's default path safe: when the source audio is already AAC, requesting AAC
            // output simply matches (no forced transcode, confirmed by the passing
            // small_480p.mp4 transmux case), so passthrough still copies; when the source audio
            // is present but NOT AAC, this same unconditional request is what makes Media3
            // transcode it to AAC rather than failing outright or trying to mux an incompatible
            // codec into the output MP4 (D-14) -- there is deliberately no separate "is this
            // AAC" branch here because the one unconditional call already covers both outcomes.
            //
            // Explicit InAppMp4Muxer.Factory with streamable output DISABLED -- found and fixed
            // plan 02-04 (Rule 1 bug, orchestrator-flagged): Transformer.Builder's own default
            // muxer (DefaultMuxer.Factory, confirmed via javap on the installed
            // media3-transformer:1.11.1 AAR) already delegates to InAppMp4Muxer with
            // attemptStreamableOutputEnabled left at ITS OWN default of true. That default
            // writes moov before mdat (so playback can start before the file finishes
            // downloading) by reserving a speculative `free` box after moov sized for moov to
            // grow into as samples arrive, then leaves whatever is unused as a real `free` box
            // in the final file. For a short, few-sample clip that reservation dwarfs the actual
            // content: a raw MP4-box walk of a remuxed small_480p.mp4 (77,504 input bytes) found
            // a single 395,344-byte `free` box -- the entire cause of a measured 472,825-byte
            // "remux" of a 77KB clip, not muxer overhead in any normal sense. Disabling
            // streamable output removes that reservation entirely (the same remux then measures
            // 77,481 bytes, smaller than the input) at the cost of moov landing at the end of the
            // file instead of the start; this plugin's output is written to local storage for the
            // caller to read as a whole file, not progressively streamed while still being
            // written, so that cost is not a real one here.
            val transformer =
                Transformer.Builder(context)
                    .setVideoMimeType(resolvedVideoMimeType)
                    .setAudioMimeType(MimeTypes.AUDIO_AAC)
                    .setEncoderFactory(encoderFactory)
                    .setMuxerFactory(InAppMp4Muxer.Factory().setAttemptStreamableOutputEnabled(false))
                    .addListener(listener)
                    .build()

            val attemptTempFile = PluginFiles.tempFileBeside(destinationFile)
            val progressHolder = ProgressHolder()
            // A dedicated scope for firing fire-and-forget progress events from the (non-suspend)
            // Runnable below -- cancelled once this attempt settles so it never outlives it.
            val progressScope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
            lateinit var progressRunnable: Runnable
            progressRunnable =
                Runnable {
                    val state = transformer.getProgress(progressHolder)
                    if (state == Transformer.PROGRESS_STATE_AVAILABLE) {
                        // Clamp into 0..99, not 0..100: measured live plan 02-06 -- the exporter
                        // can report PROGRESS_STATE_AVAILABLE with progress already at 100 for
                        // several poll ticks BEFORE onCompleted actually fires
                        // (muxing/finalisation happens after the reported progress reaches its
                        // own ceiling), which would forward 100 multiple times if this loop's own
                        // upper clamp allowed it through. The single canonical terminal 100 is
                        // reserved for the explicit onProgress(100.0) call made once, right
                        // before the success/never-larger/remux-shortcut reply below -- this is
                        // what guarantees 100 appears exactly once in the whole stream, per
                        // 02-06-PLAN.md task 1's acceptance criteria. Never forward a value
                        // smaller than the last one actually sent for this JOB (shared across
                        // every attempt, see [lastSentProgress] above), either --
                        // monotonically non-decreasing even across a retry.
                        val clamped = progressHolder.progress.toDouble().coerceIn(0.0, 99.0)
                        val forwarded = maxOf(clamped, lastSentProgress)
                        lastSentProgress = forwarded
                        progressScope.launch { onProgress(forwarded) }
                    }
                    // The class javadoc: "After an export completes, this method returns
                    // PROGRESS_STATE_NOT_STARTED" -- the terminal Transformer.Listener callbacks
                    // above call JobRegistry.stopPolling the instant they fire (rather than
                    // relying on this state change, or on JobRegistry.remove/cancel after this
                    // suspend function resumes) to stop this loop on every terminal path.
                    mainHandler.postDelayed(progressRunnable, PROGRESS_POLL_INTERVAL_MS)
                }

            JobRegistry.register(
                jobId,
                JobRegistry.LiveJob(
                    cancelTransformer = { transformer.cancel() },
                    tempFile = attemptTempFile,
                    mainHandler = mainHandler,
                    progressRunnable = progressRunnable,
                    onCancelled = { attemptDeferred.complete(ExportOutcome.Cancelled) },
                ),
            )

            mainHandler.post(progressRunnable)
            transformer.start(composition, attemptTempFile.path)

            val attemptOutcome = attemptDeferred.await()
            JobRegistry.remove(jobId)
            progressScope.cancel()
            return attemptOutcome to attemptTempFile
        }

        var (outcome, tempFile) =
            attemptExport(resolveHdrMode(inputInfo.isHdr, keepHdrAchievable))
        var triedMediaCodecFallback = false

        // The retry chain (04-RESEARCH.md Pattern 2): only for a genuinely HDR source under the
        // default tone-map request, only after a real export FAILURE (never a cancellation --
        // ExportOutcome.Cancelled is a distinct case below and is always terminal on the first
        // attempt), and only where the MediaCodec tone-map path is even available (API 31+).
        // Retrying an ordinary (non-HDR) failure would double its cost to serve a case that
        // cannot benefit -- a regression this condition exists specifically to prevent.
        if (outcome is ExportOutcome.Failure &&
            isHdrToneMapAttempt &&
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.S
        ) {
            // The failed attempt's temp file is deleted BEFORE the retry starts, not after --
            // a retry against a stale file left behind by the first attempt is a different bug
            // wearing the first one's clothes (04-RESEARCH.md Anti-Patterns).
            PluginFiles.quietDelete(tempFile)
            triedMediaCodecFallback = true
            val retryResult =
                attemptExport(Composition.HDR_MODE_TONE_MAP_HDR_TO_SDR_USING_MEDIACODEC)
            outcome = retryResult.first
            tempFile = retryResult.second
        }

        return when (val finalOutcome = outcome) {
            is ExportOutcome.Cancelled -> {
                PluginFiles.quietDelete(tempFile)
                throw CompressVideoError("cancelled", "The compression job was cancelled")
            }
            is ExportOutcome.Failure -> {
                PluginFiles.quietDelete(tempFile)
                if (isHdrToneMapAttempt) {
                    throw hdrFallbackExhaustedError(finalOutcome.exception, triedMediaCodecFallback)
                } else {
                    throw mapExportException(finalOutcome.exception)
                }
            }
            is ExportOutcome.Success -> {
                onProgress(100.0)
                finishSuccess(
                    finalOutcome.exportResult,
                    tempFile,
                    destinationFile,
                    inputFile,
                    inputBytes,
                    startElapsedMs,
                    inputWasHdr = inputInfo.isHdr,
                    hevcFallbackFromRequest = hevcFallback,
                    audioEncodeForced =
                        request.audioMode == AudioModeMessage.REENCODE || audioForcedReencode,
                )
            }
        }
    }

    /**
     * Throws when the HDR tone-map fallback chain (04-RESEARCH.md Pattern 2) is exhausted:
     * neither `HDR_MODE_TONE_MAP_HDR_TO_SDR_USING_OPEN_GL` nor (when [triedMediaCodecFallback])
     * `_USING_MEDIACODEC` succeeded on this device. Reason `unsupportedInput` -- there is nothing
     * more this engine can attempt on this hardware, not a malformed request -- with
     * [lastException]'s own `errorCode` folded into the message, following [mapExportException]'s
     * own convention so the numeric code stays observable from Dart even though the reason is
     * recognised (`CompressVideoException.platformDetail` is only populated Dart-side for an
     * unrecognised reason NAME, per [mapExportException]'s own doc comment). No new
     * [CompressVideoErrorReason] value is added -- `unsupportedInput` already exists.
     */
    private fun hdrFallbackExhaustedError(
        lastException: ExportException,
        triedMediaCodecFallback: Boolean,
    ): CompressVideoError {
        val chain =
            if (triedMediaCodecFallback) {
                "the OpenGL then MediaCodec HDR tone-map paths"
            } else {
                "the OpenGL HDR tone-map path (MediaCodec fallback unavailable below API 31)"
            }
        val detailMessage = lastException.message?.let { ": $it" } ?: ""
        val message =
            "No supported HDR tone-map path on this device -- exhausted $chain " +
                "(Media3 export failed with code ${lastException.errorCode}$detailMessage)"
        return CompressVideoError("unsupportedInput", message, lastException.errorCode.toString())
    }

    /**
     * Resolves the probed input's own [inputIsHdr] flag plus [keepHdrAchievable] (04-03,
     * CDEC-03 -- computed once in [compress] via [resolveKeepHdrAchievable], the SAME shared
     * decision that also gates [compress]'s own video-MIME choice) into the [Composition]
     * HdrMode int Transformer actually understands (04-RESEARCH.md Pattern 1).
     *
     * For a NON-HDR input this MUST resolve to [Composition.HDR_MODE_KEEP_HDR] (`0`), not the
     * tone-map mode -- found live in 04-02, not assumed: `TransformerUtil.shouldTranscodeVideo`
     * (confirmed via `javap` against the installed media3-transformer-1.11.1 AAR) forces a
     * transcode whenever `TransformationRequest.hdrMode` is non-zero, REGARDLESS of whether the
     * input is actually HDR. Requesting the tone-map mode unconditionally silently broke the
     * transmux fast path for every ordinary H.264 clip (`small_480p.mp4` stopped transmuxing
     * when this was first written that way). `HDR_MODE_KEEP_HDR` is a harmless no-op for a
     * non-HDR source (04-RESEARCH.md Pattern 1) and is the only value that leaves
     * `shouldTranscodeVideo`'s decision to the ordinary mime-type/effects comparison, so this
     * function is not a cosmetic default -- it is what keeps CDEC-02 from regressing CORE-06.
     *
     * For an HDR input, [Composition.HDR_MODE_KEEP_HDR] is ALSO the right value when
     * [keepHdrAchievable] is true (04-03, CDEC-03): a genuine keep-HDR encode, not the harmless
     * no-op above. Otherwise this resolves to
     * [Composition.HDR_MODE_TONE_MAP_HDR_TO_SDR_USING_OPEN_GL] -- the first attempt in 04-02
     * task 2's OpenGL-then-MediaCodec fallback chain, which covers both the default
     * `toneMapToSdr` request and an unachievable `keepHdr` request (D-08's fallback).
     *
     * Media3's own automatic step-down from `HDR_MODE_KEEP_HDR` for a device that cannot honour
     * it (04-RESEARCH.md Pattern 4) is never relied on here as a fallback mechanism: it silently
     * changes only the HDR mode, never the requested video MIME type, which on an incapable
     * device would produce HEVC 8-bit SDR instead of the required H.264 SDR fallback. It stays
     * as defence in depth against [keepHdrAchievable] disagreeing with reality, not as the
     * fallback -- [resolveKeepHdrAchievable]'s own hardware-capability gate is what decides
     * H.264-vs-HEVC output, independently and before this function ever runs.
     */
    private fun resolveHdrMode(
        inputIsHdr: Boolean,
        keepHdrAchievable: Boolean,
    ): Int {
        if (!inputIsHdr || keepHdrAchievable) {
            return Composition.HDR_MODE_KEEP_HDR
        }
        return Composition.HDR_MODE_TONE_MAP_HDR_TO_SDR_USING_OPEN_GL
    }

    /**
     * Resolves a [ChannelMixingMatrix] for [inputChannels] to [outputChannels], special-casing
     * 6-to-2 (5.1 to stereo). [ChannelMixingMatrix.createForConstantGain] does NOT implement
     * every pair -- confirmed live this task, not assumed from 04-RESEARCH.md's "Don't Hand-Roll"
     * citation: `createForConstantGain(6, 2)` throws
     * `UnsupportedOperationException("Default channel mixing coefficients for 6->2 are not yet
     * implemented.")` on the installed media3-common-1.11.1 AAR. [fiveDotOneToStereoMixingMatrix]
     * supplies the one additional pair AUDO-03 needs; every other pair this plugin actually
     * requests (mono<->stereo, for [AudioReencode]'s 1-or-2-channel range) already works through
     * the library default and is left alone.
     */
    private fun channelMixingMatrixFor(
        inputChannels: Int,
        outputChannels: Int,
    ): ChannelMixingMatrix =
        if (inputChannels == 6 && outputChannels == 2) {
            fiveDotOneToStereoMixingMatrix()
        } else {
            ChannelMixingMatrix.createForConstantGain(inputChannels, outputChannels)
        }

    /**
     * A fixed-coefficient 5.1-to-stereo [ChannelMixingMatrix], since Media3 has no built-in
     * default for this pair (see [channelMixingMatrixFor]'s doc comment). Assumes the standard
     * Android 5.1 channel order (`AudioFormat.CHANNEL_OUT_5POINT1`): front-left, front-right,
     * front-centre, LFE, back-left, back-right. Coefficients follow the common ITU-R
     * BS.775-inspired downmix every mainstream consumer decoder uses: each front channel passes
     * straight through to its own side, the centre and each surround channel contribute to BOTH
     * output channels at [SURROUND_DOWNMIX_GAIN] (-3dB), and LFE is not folded in at all --
     * matching how most consumer downmix implementations treat the sub channel by default.
     */
    private fun fiveDotOneToStereoMixingMatrix(): ChannelMixingMatrix {
        val g = SURROUND_DOWNMIX_GAIN
        // Row-major, input-channel-major (confirmed via javap against the installed
        // media3-common-1.11.1 AAR's ChannelMixingMatrix.getMixingCoefficient(int, int)):
        // coefficients[inputChannelIndex * outputChannelCount + outputChannelIndex].
        val coefficients =
            floatArrayOf(
                // FL -> L, R
                1f, 0f,
                // FR -> L, R
                0f, 1f,
                // FC -> L, R
                g, g,
                // LFE -> L, R (not folded in)
                0f, 0f,
                // BL -> L, R
                g, 0f,
                // BR -> L, R
                0f, g,
            )
        return ChannelMixingMatrix(6, 2, coefficients)
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
        inputWasHdr: Boolean,
        hevcFallbackFromRequest: Boolean,
        audioEncodeForced: Boolean,
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
        // Found live this task (Rule 1 bug, not assumed): for a raw PCM source, Media3 reports
        // ExportResult.audioConversionProcess as CONVERSION_PROCESS_TRANSMUXED (2), never
        // TRANSCODED, EVEN THOUGH a real AudioEncoderSettings-driven encode ran and the produced
        // file re-probes as genuine AAC (confirmed via readAudioCodec on the destination file
        // in a case that forced exactly this path) -- the DECODE side of a raw/PCM track needs
        // no real decoder, and Media3's own conversion-process classification apparently reflects
        // that trivial decode step rather than the real encode step for this specific source
        // shape. TransformerUtil.shouldTranscodeAudio's own bytecode (javap-verified against the
        // installed media3-transformer-1.11.1 AAR) proves audioNeedsEncoding()==true --
        // unconditionally true whenever this engine sets explicit AudioEncoderSettings --
        // ALWAYS forces Media3 down the real transcode path, before any mime-type comparison;
        // [audioEncodeForced] mirrors that exact same decision, so it is trusted directly for
        // this one ambiguous enum value rather than treated as a guess.
        val audioReencoded =
            !usedOriginal &&
                (
                    exportResult.audioConversionProcess ==
                        ExportResult.CONVERSION_PROCESS_TRANSCODED ||
                        exportResult.audioConversionProcess ==
                        ExportResult.CONVERSION_PROCESS_TRANSMUXED_AND_TRANSCODED ||
                        audioEncodeForced
                )

        // Computed from the export's OWN output colour info via ColorInfo.isTransferHdr, never
        // from what the request asked for (04-RESEARCH.md Pattern 5) -- the caller is told
        // whether the file they RECEIVED is tone-mapped, not whether tone-mapping was requested.
        // Guarded by !usedOriginal exactly like transmuxed/audioReencoded above: a substituted
        // original was never tone-mapped, whatever Media3 did to the temp file this job
        // discarded. An HDR input can never reach the transmux fast path either way --
        // SizeGuard's wouldTransmux predicate requires an H.264 video codec, and every HDR
        // source in this corpus is HEVC -- so the only two paths an HDR clip can take are a
        // real encode (this branch) or the never-larger substitution above; there is no third
        // case this formula needs to reconcile.
        val outputIsHdr = exportResult.colorInfo?.let { ColorInfo.isTransferHdr(it) } ?: false
        val toneMapped = !usedOriginal && inputWasHdr && !outputIsHdr

        // Guarded by !usedOriginal exactly like transmuxed/audioReencoded/toneMapped above: a
        // substituted original never "fell back" to anything, whatever [hevcFallbackFromRequest]
        // (computed in [compress], before this export even ran) says.
        val hevcFallback = !usedOriginal && hevcFallbackFromRequest

        return buildResultFromDestination(
            destinationFile = destinationFile,
            inputBytes = inputBytes,
            startElapsedMs = startElapsedMs,
            transmuxed = transmuxed,
            usedOriginal = usedOriginal,
            audioReencoded = audioReencoded,
            toneMapped = toneMapped,
            hevcFallback = hevcFallback,
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
        toneMapped: Boolean,
        hevcFallback: Boolean,
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
            toneMapped = toneMapped,
            hevcFallback = hevcFallback,
            audioReencoded = audioReencoded,
            elapsedMs = SystemClock.elapsedRealtime() - startElapsedMs,
        )
    }

    /**
     * Reads the normalised codec of [file]'s first audio track, or `null` if it has none.
     * Mirrors [Probe]'s own extractor-scan pattern without modifying that file. Runs on
     * [Dispatchers.IO] (WR-04): [MediaExtractor.setDataSource] performs a real file-open and
     * container-header parse, which must not block the main Looper this is called from.
     */
    private suspend fun readAudioCodec(file: File): String? =
        withContext(Dispatchers.IO) {
            val extractor = MediaExtractor()
            try {
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
     * encoder is asked to produce, never what the caller is told about the source). Runs on
     * [Dispatchers.IO] (WR-04), same rationale as [readAudioCodec].
     */
    private suspend fun readAudioChannelCount(file: File): Int? =
        withContext(Dispatchers.IO) {
            val extractor = MediaExtractor()
            try {
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
     * Never opens [source] for writing. Runs on [Dispatchers.IO] (CR-01): both call sites
     * ([compress]'s pre-check fast path and [finishSuccess]'s post-check fallback) can be a
     * multi-hundred-megabyte-to-multi-gigabyte disk-to-disk copy, and both used to run it
     * synchronously on the calling (main) thread. [Dispatchers.IO] always resumes back on the
     * caller's original context once the block completes, so no [Transformer] or [JobRegistry]
     * access ever happens off the main Looper.
     */
    private suspend fun copyFileAtomically(
        source: File,
        destination: File,
    ) = withContext(Dispatchers.IO) {
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
     * Resolves [request] against [inputInfo] into a [SizeGuard.Plan], reading [inputFile]'s own
     * audio codec first when it has an audio track (needed by [SizeGuard.Plan.wouldTransmux]'s
     * audio-codec condition, D-10). Exposed (not `private`) so [Compression]'s pre-flight
     * free-space check can predict the SAME plan [compress] itself will resolve, before a
     * `Transformer` is ever built -- both call sites must resolve identically, or the free-space
     * check could pass or fail against a prediction the actual encode does not honour. Suspend
     * (WR-04): [readAudioCodec] now dispatches its native read to [Dispatchers.IO].
     */
    suspend fun resolvePlan(
        inputFile: File,
        inputInfo: MediaInfoMessage,
        request: CompressRequestMessage,
    ): SizeGuard.Plan {
        val inputAudioCodec = if (inputInfo.hasAudio) readAudioCodec(inputFile) else null
        // Read the same way audioCodec is, immediately above (AUDO-03, 04-02-PLAN.md task 3):
        // needed by SizeGuard.Plan.wouldTransmux's channel-count condition, so estimate() and
        // the real job -- both of which call resolvePlan and nothing else to get a Plan -- can
        // never resolve a different answer about whether a 5.1 source would remux.
        val inputAudioChannels = if (inputInfo.hasAudio) readAudioChannelCount(inputFile) else null
        // The SAME hardware-HEVC/keep-HDR decisions [compress] itself computes for its own MIME
        // gate (04-03, CDEC-01/03) -- calling them here too, rather than threading a value in
        // from [compress], means resolvePlan alone (as [Compression]'s free-space pre-check and
        // estimate() both call it) can independently resolve the identical
        // SizeGuard.Options.outputCodecIsHevc [compress] resolves, with no risk of the two ever
        // drifting apart.
        val requestedHevc = request.videoCodec == "hevc"
        val outputCodecIsHevc =
            (requestedHevc && hasHardwareHevcEncoder()) ||
                resolveKeepHdrAchievable(inputFile, inputInfo.isHdr, request.hdrMode == "keepHdr")
        return SizeGuard.resolve(
            buildSizeGuardInput(inputInfo, inputAudioCodec, inputAudioChannels),
            buildSizeGuardOptions(request, outputCodecIsHevc),
        )
    }

    /**
     * Whether this device has a hardware-accelerated encoder for [MimeTypes.VIDEO_H265]
     * (CDEC-01), dispatched to [Dispatchers.IO] (WR-04) since [CodecCapabilities.hasHardwareEncoder]
     * enumerates the platform's own codec list -- a real native probe. Called identically from
     * [compress]'s own MIME/hevcFallback gate and from [resolvePlan] (for
     * [SizeGuard.Options.outputCodecIsHevc]), so a request's HEVC decision can never disagree
     * between the two call sites (04-RESEARCH.md Pattern 3/4; the estimate()/compress()
     * agreement invariant established in 02-07).
     */
    private suspend fun hasHardwareHevcEncoder(): Boolean =
        withContext(Dispatchers.IO) { CodecCapabilities.hasHardwareEncoder(MimeTypes.VIDEO_H265) }

    /**
     * Whether a keep-HDR request (04-03, CDEC-03) is genuinely achievable: `false` immediately
     * when [requestedKeepHdr] is `false` or [inputIsHdr] is `false` (nothing to keep), otherwise
     * `true` only when [inputFile]'s own colour transfer is readable AND
     * [CodecCapabilities.supportsHdrEditing] finds a hardware encoder that can keep it. Called
     * identically from [compress]'s own MIME/HdrMode/hevcFallback gates and from [resolvePlan]
     * (for [SizeGuard.Options.outputCodecIsHevc]), so a request's keep-HDR decision can never
     * disagree between the two call sites -- the same invariant [hasHardwareHevcEncoder]'s own
     * doc comment states, extended to cover keep-HDR.
     */
    private suspend fun resolveKeepHdrAchievable(
        inputFile: File,
        inputIsHdr: Boolean,
        requestedKeepHdr: Boolean,
    ): Boolean {
        if (!requestedKeepHdr || !inputIsHdr) {
            return false
        }
        val colorTransfer = readColorTransfer(inputFile) ?: return false
        return hasHardwareHdrEditingSupport(colorTransfer)
    }

    /**
     * Reads [file]'s own colour transfer characteristic as a Media3 [C.COLOR_TRANSFER_*] int, or
     * `null` when unavailable (below API 30, no HDR transfer characteristic reported, or any
     * exception) -- mirrors [Probe.isHdr]'s own [MediaMetadataRetriever.METADATA_KEY_COLOR_TRANSFER]
     * read and its `Build.VERSION_CODES.R` gate exactly (04-RESEARCH.md Pattern 3: the platform's
     * own `MediaFormat.COLOR_TRANSFER_HLG`/`_ST2084` ints are the SAME values as Media3's
     * `C.COLOR_TRANSFER_HLG`/`_ST2084`, verified via `javap`, so the raw int passes straight
     * through into a [ColorInfo] with no translation needed). Runs on [Dispatchers.IO] (WR-04),
     * same rationale as [readAudioCodec]/[readAudioChannelCount].
     */
    private suspend fun readColorTransfer(file: File): Int? =
        withContext(Dispatchers.IO) {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) {
                return@withContext null
            }
            val retriever = MediaMetadataRetriever()
            try {
                retriever.setDataSource(file.path)
                retriever
                    .extractMetadata(MediaMetadataRetriever.METADATA_KEY_COLOR_TRANSFER)
                    ?.toIntOrNull()
            } catch (e: Exception) {
                null
            } finally {
                retriever.release()
            }
        }

    /**
     * Whether this device can genuinely keep HDR (CDEC-03, D-07) for a source whose colour
     * transfer is [colorTransfer] (HLG or PQ, read via [readColorTransfer]): builds the
     * [ColorInfo] [CodecCapabilities.supportsHdrEditing] needs from [colorTransfer] plus
     * [C.COLOR_SPACE_BT2020]/[C.COLOR_RANGE_LIMITED] -- every HDR clip this plugin's own corpus
     * carries is BT.2020/limited-range (04-RESEARCH.md Pattern 3), and [Probe.isHdr]'s own
     * detection is scoped to exactly the two transfer functions [colorTransfer] can be here
     * (HLG, PQ). Dispatched to [Dispatchers.IO] (WR-04), same rationale as
     * [hasHardwareHevcEncoder].
     */
    private suspend fun hasHardwareHdrEditingSupport(colorTransfer: Int): Boolean =
        withContext(Dispatchers.IO) {
            val colorInfo =
                ColorInfo.Builder()
                    .setColorSpace(C.COLOR_SPACE_BT2020)
                    .setColorTransfer(colorTransfer)
                    .setColorRange(C.COLOR_RANGE_LIMITED)
                    .build()
            CodecCapabilities.supportsHdrEditing(colorInfo)
        }

    /**
     * Builds [SizeGuard.InputInfo] from the probed [inputInfo]. [MediaInfoMessage] itself has no
     * audio-codec or audio-channel-count field (see [readAudioCodec]/[readAudioChannelCount]'s
     * own doc comments), so both are read separately by [resolvePlan] and threaded through here
     * -- needed by [SizeGuard.Plan.wouldTransmux]'s audio-codec (D-10) and audio-channel-count
     * (AUDO-03) conditions, neither of which [SizeGuard.InputInfo.audioBitrateBps] alone can
     * answer.
     */
    private fun buildSizeGuardInput(
        inputInfo: MediaInfoMessage,
        audioCodec: String?,
        audioChannelCount: Int?,
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
            audioChannelCount = audioChannelCount,
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
    private fun buildSizeGuardOptions(
        request: CompressRequestMessage,
        outputCodecIsHevc: Boolean,
    ): SizeGuard.Options =
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
            outputCodecIsHevc = outputCodecIsHevc,
        )

    /**
     * Maps [ExportException.errorCode] to a [CompressVideoError] reason per the table in
     * 02-RESEARCH.md (its own Pitfalls #8/#9 explain the choices CONTEXT.md left as "per
     * research").
     */
    /**
     * Maps [exception] to a [CompressVideoError] via [ErrorMapping] -- the pure, JVM-testable
     * table this plan (02-06) extracted from what used to be this function's own inline
     * `when` block, plus [ErrorMapping.reasonForExportFailure]'s out-of-space message check
     * ([exception]'s underlying `cause`, since [ExportException] itself carries no dedicated
     * out-of-space code). Called from [compress]'s failure path, itself called AFTER the temp
     * file has already been deleted (D-18, T-02-21): no failure path here writes to the
     * platform log, and the original numeric [ExportException.errorCode] is always preserved as
     * the error's detail, even when the reason is `"unknown"`.
     */
    private fun mapExportException(exception: ExportException): CompressVideoError {
        val reason =
            ErrorMapping.reasonForExportFailure(exception.errorCode, exception.cause?.message)
        // The numeric errorCode is always folded into the message text, not left to the
        // platformDetail round trip alone -- CompressVideoException.platformDetail is only
        // populated Dart-side when the mapped reason is "unknown" (see
        // reasonFromPlatformCode/_wrapPlatformException), so a recognised reason like "io"
        // would otherwise make the original ExportException.errorCode unobservable from Dart,
        // defeating the whole point of this plan's error-mapping work when a caller needs to
        // paste the exact code into an issue report.
        val detailMessage = exception.message?.let { ": $it" } ?: ""
        val message = "Media3 export failed with code ${exception.errorCode}$detailMessage"
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
         * The value of `toneMapped` AND `hevcFallback` when [compress]'s never-larger pre-check
         * short-circuits before a [Transformer] is ever built: neither tone-mapping nor an HEVC
         * fallback can have happened when no encode ran at all. Named rather than a bare literal
         * so this file's own real [ColorInfo.isTransferHdr]-derived (see [finishSuccess]) and
         * request-derived (04-03, CDEC-01) computations are never mistaken for another leftover
         * hardcoded value.
         */
        private const val NO_TRANSFORM_ATTEMPTED = false

        /** The normalised audio codec token [normalizeAudioCodec] returns for AAC. */
        private const val AUDIO_CODEC_AAC_TOKEN = "aac"

        /**
         * The channel count AUDO-03's forced re-encode caps its target at (AUDO-03, 04-02-PLAN.md
         * task 3): a 5.1 (or wider) source downmixes to stereo, never wider. Also used as the
         * fallback source-channel-count assumption when the source's own count could not be read
         * at all -- an unreadable count on a path already forcing a re-encode still needs a
         * concrete target, and 2 is this plugin's own audio default everywhere else.
         */
        private const val FORCED_AUDIO_REENCODE_MAX_CHANNELS = 2

        /**
         * The fixed audio bitrate AUDO-03's forced re-encode targets, in bits per second --
         * deliberately not [SizeGuard.Plan.audioBitrateBps]: that value is SizeGuard rule 5's
         * resolution of the SOURCE's own audio bitrate, which describes six channels or raw
         * LPCM here and is the wrong number to hand a 1-or-2-channel AAC encoder (04-RESEARCH.md
         * Pitfall 1).
         */
        private const val FORCED_AUDIO_REENCODE_BITRATE_BPS = 128000

        /**
         * The gain [fiveDotOneToStereoMixingMatrix] applies from the centre and each surround
         * channel into both stereo outputs: -3dB, `10^(-3/20)` rounded to 7 significant figures,
         * the standard ITU-R BS.775-inspired downmix attenuation.
         */
        private const val SURROUND_DOWNMIX_GAIN = 0.7071068f

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
