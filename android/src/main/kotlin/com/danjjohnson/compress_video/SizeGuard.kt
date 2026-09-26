package com.danjjohnson.compress_video

import kotlin.math.ceil

/**
 * Pure preset/explicit-target/target-size resolution shared by the compress path and the
 * estimate path.
 *
 * No Android framework import and no Media3 import -- exercisable as plain JVM code with no
 * Looper and no emulator, exactly like [MediaMath], because `estimate()` (plan 02-07) must be
 * able to call the same resolution [TransformerEngine] uses without ever touching a decoder.
 * [SizeGuardTest] is the JVM suite that proves every rule below without an emulator.
 *
 * Implements the seven-rule resolution contract in 02-03-PLAN.md exactly, in order, plus the
 * transmux (D-10) and never-larger (D-11) predicates added in plan 02-04. Both predicates are
 * pure derivations of numbers this function already computes, so the compress path and the
 * future `estimate()` path (plan 02-07) can never disagree about whether a request would remux,
 * substitute the original, or genuinely encode -- 02-04-PLAN.md's must-have that
 * `CompressEstimate.wouldTransmux`/`wouldUseOriginal` can never diverge from what the job
 * actually does.
 */
object SizeGuard {
    /**
     * The probed facts about the input file [SizeGuard] needs. `null` on any nullable field
     * means "the platform could not determine this" -- never a sentinel `0` or empty string
     * (mirroring [MediaInfoMessage]'s own contract).
     */
    data class InputInfo(
        /** Displayed (rotation-corrected) width, in pixels. */
        val displayedWidthPx: Int,
        /** Displayed (rotation-corrected) height, in pixels. */
        val displayedHeightPx: Int,
        /** Unsigned clockwise rotation, in degrees, as reported before display-correction. */
        val rotationDegrees: Int,
        /** Duration of the input, in milliseconds. */
        val durationMs: Long,
        /** Size of the input file, in bytes. */
        val sizeBytes: Long,
        /** Normalised video codec token (see [MediaMath.normalizeCodec]). */
        val videoCodec: String,
        /** Average video-track bitrate, in bits per second, or `null` when unknown. */
        val videoBitrateBps: Long?,
        /** Video frame rate, in frames per second, or `null` when unknown. */
        val frameRateFps: Double?,
        /** Whether the input has at least one audio track. */
        val hasAudio: Boolean,
        /** Normalised audio codec token, or `null` when [hasAudio] is `false` or unknown. */
        val audioCodec: String?,
        /** Average audio-track bitrate, in bits per second, or `null` when unknown. */
        val audioBitrateBps: Long?,
        /**
         * `audioChannelCount`: the input's own audio channel count, or `null` when [hasAudio] is
         * `false` or the platform could not determine it. Defaults to `null` so every
         * pre-existing call site that constructs an [InputInfo] without this field keeps
         * compiling unchanged (04-02). Feeds [wouldTransmux]'s `audioChannelCount` condition
         * (AUDO-03): a `null` value is treated as "unknown, assume safe to remux" exactly like
         * [videoBitrateBps]'s own unknown-input handling elsewhere in this file, since a
         * genuinely-unknown channel count is not evidence of a six-channel track.
         */
        val audioChannelCount: Int? = null,
    )

    /** The video codec token that satisfies [wouldTransmux]'s codec condition (D-10). */
    private const val VIDEO_CODEC_H264 = "h264"

    /** The audio codec token that satisfies [wouldTransmux]'s audio-codec condition (D-10). */
    private const val AUDIO_CODEC_AAC = "aac"

    /** The channel count that satisfies [wouldTransmux]'s audio-channel-count condition (AUDO-03). */
    private const val MAX_TRANSMUX_AUDIO_CHANNELS = 2

    /**
     * The resolved request [SizeGuard] resolves against an [InputInfo].
     *
     * [maxLongSidePx] and [videoBitrateBps] are explicit-override-or-`null` -- `null` means
     * "the caller did not set this field", which is what lets rule 6 tell an explicit bitrate
     * request apart from one that must fall back to preset scaling. [presetMaxLongSidePx] and
     * [presetVideoBitrateBps] are always the selected `CompressPreset`'s own nominal values,
     * sent regardless of any override, because they are the fixed reference the bitrate-scaling
     * formula (rule 6) divides by -- an override changes the *target*, never the *reference*.
     */
    data class Options(
        /** Explicit cap on the output's longer displayed side, in pixels, or `null`. */
        val maxLongSidePx: Long?,
        /** Explicit target video bitrate, in bits per second, or `null`. */
        val videoBitrateBps: Long?,
        /** Explicit target output size, in megabytes (1,000,000 bytes each), or `null`. */
        val targetSizeMb: Double?,
        /** The selected preset's own nominal long-side cap, in pixels. Always set. */
        val presetMaxLongSidePx: Long,
        /** The selected preset's own nominal video bitrate, in bits per second. Always set. */
        val presetVideoBitrateBps: Long,
        /** Cap on the output's frame rate, in frames per second. Never upscales. */
        val maxFps: Long,
        /** Whether the audio track is being removed entirely. */
        val audioStripped: Boolean,
        /**
         * Whether the request is `AudioModeMessage.PASSTHROUGH` -- distinct from
         * [audioStripped] (`STRIP`) and a forced re-encode (`REENCODE`). [wouldTransmux]'s
         * audio-mode condition (D-10) is only satisfied by an explicit passthrough request; a
         * caller asking to strip or re-encode audio must not be told the job would remux.
         */
        val audioPassthroughRequested: Boolean,
        /** Explicit requested audio bitrate (only meaningful for a re-encode), or `null`. */
        val requestedAudioBitrateBps: Long?,
        /** Start of the trim range, in milliseconds, or `null` for the start of the input. */
        val trimStartMs: Long?,
        /** End of the trim range, in milliseconds, or `null` for the end of the input. */
        val trimEndMs: Long?,
    )

    /**
     * The resolved plan: everything [TransformerEngine] needs to build Media3 objects without
     * computing any of its own scaling arithmetic.
     */
    data class Plan(
        /** Resolved output width, in pixels. Always even and at least 16. */
        val targetWidthPx: Int,
        /** Resolved output height, in pixels. Always even and at least 16. */
        val targetHeightPx: Int,
        /** Resolved output frame rate, in frames per second. Never above the input's own. */
        val effectiveFps: Int,
        /** Resolved video bitrate, in bits per second. Never above the input's own, when known. */
        val videoBitrateBps: Long,
        /** Resolved audio bitrate, in bits per second. `0` when the audio is stripped. */
        val audioBitrateBps: Long,
        /** Resolved output duration, in milliseconds -- the trimmed duration when trimmed. */
        val outputDurationMs: Long,
        /**
         * Predicted output file size, in bytes, including estimated container overhead. Exactly
         * [InputInfo.sizeBytes] when [wouldTransmux] is `true`, since a remux copies the same
         * samples rather than re-encoding them.
         */
        val predictedOutputBytes: Long,
        /**
         * Whether Media3 would be ASKED to remux (container copy, no video re-encode) rather
         * than transcode, decided from the exact seven conditions in 02-04-PLAN.md's "The
         * decision order this plan fixes" / D-10. This is a pre-flight recommendation for which
         * operation [TransformerEngine.compress] attempts, and which encoder settings to build
         * -- it is NOT a guarantee about the bytes the caller ultimately receives. The engine
         * always re-verifies the real output against [InputInfo.sizeBytes] after the job runs
         * (see [wouldUseOriginal]'s own note), whichever operation it attempted, and a remux
         * whose real output is not smaller than the input is discarded exactly like a real
         * encode would be -- CORE-05 describes the file the caller receives, not the operation
         * that was attempted.
         */
        val wouldTransmux: Boolean,
        /**
         * Whether [TransformerEngine.compress] should skip attempting an encode at all and copy
         * the original input to the output path instead, because [wouldTransmux] is `false` and
         * [predictedOutputBytes] is already greater than or equal to [InputInfo.sizeBytes] --
         * equality counts as "would not help" (D-11, CORE-05). This is the PRE-flight check
         * only, deciding whether it is worth even attempting an operation; it is `false`
         * whenever [wouldTransmux] is `true` because a remux is cheap enough, and often
         * successful enough, that it is always worth attempting rather than skipped outright.
         * The engine's POST-check, applied unconditionally to whatever real bytes an attempted
         * remux OR a real encode actually produced, is a separate, later decision that this
         * field does not by itself determine -- a `false` here does not mean the final returned
         * file can never be the original; it means only that an attempt is worth making.
         */
        val wouldUseOriginal: Boolean,
    )

    /**
     * Resolves [options] against [input] into a [Plan], applying every rule in
     * 02-03-PLAN.md's "The resolution contract this plan implements" in order.
     */
    fun resolve(
        input: InputInfo,
        options: Options,
    ): Plan {
        // Rule 1: effectiveLongSidePx never exceeds the input's own displayed long side.
        val inputLongSidePx = maxOf(input.displayedWidthPx, input.displayedHeightPx)
        val requestedLongSidePx = options.maxLongSidePx ?: options.presetMaxLongSidePx
        val effectiveLongSidePx = minOf(requestedLongSidePx, inputLongSidePx.toLong())

        // Rule 2.
        val scale = effectiveLongSidePx.toDouble() / inputLongSidePx.toDouble()

        // Rule 3: both dimensions rounded down to even, floored at 16.
        val targetWidthPx = MediaMath.floorToEvenMin16(input.displayedWidthPx * scale)
        val targetHeightPx = MediaMath.floorToEvenMin16(input.displayedHeightPx * scale)

        // Rule 4: never upscale frame rate either. An unknown input frame rate uses maxFps
        // unchanged, per the rule's own stated fallback.
        val inputFpsRounded = input.frameRateFps?.let { MediaMath.roundFpsHalfUp(it) }
        val effectiveFps = minOf(options.maxFps.toInt(), inputFpsRounded ?: options.maxFps.toInt())

        // Trim-aware output duration, needed by rules 6 and 7.
        val trimStartMs = options.trimStartMs ?: 0L
        val trimEndMs = options.trimEndMs ?: input.durationMs
        val outputDurationMs = (trimEndMs - trimStartMs).coerceAtLeast(0L)
        val outputDurationSeconds = outputDurationMs / MILLIS_PER_SECOND

        // Rule 5: audio bitrate, clamped into the AAC encoder's own advertised range.
        val audioBitrateBps: Long =
            if (options.audioStripped) {
                0L
            } else {
                val requestedOrFallback =
                    options.requestedAudioBitrateBps
                        ?: input.audioBitrateBps
                        ?: DEFAULT_AUDIO_BITRATE_BPS
                requestedOrFallback.coerceIn(MIN_AUDIO_BITRATE_BPS, MAX_AUDIO_BITRATE_BPS)
            }

        // Rule 6: video bitrate, in precedence order, then capped at the input's own bitrate
        // in every branch.
        var videoBitrateBps: Long =
            when {
                options.videoBitrateBps != null -> options.videoBitrateBps
                options.targetSizeMb != null -> {
                    // WR-02: a durationless input (missing/zero duration metadata --
                    // Probe.kt defaults durationRawMs to 0.0 when METADATA_KEY_DURATION is
                    // absent, and requireReadableMediaFile only checks the file is non-empty,
                    // not that it has a readable duration) would otherwise divide by zero here,
                    // producing Double.POSITIVE_INFINITY -> Long.MAX_VALUE -> a wrapped,
                    // nonsensical Int handed straight to VideoEncoderSettings.setBitrate. There
                    // is no meaningful per-second target bitrate for zero output duration, so
                    // fall back to the same floor every other branch is already clamped to.
                    if (outputDurationSeconds <= 0.0) {
                        VIDEO_BITRATE_FLOOR_BPS
                    } else {
                        val targetTotalBitrateBps =
                            options.targetSizeMb * BYTES_PER_MEGABYTE * BITS_PER_BYTE /
                                outputDurationSeconds * MUX_OVERHEAD_FACTOR
                        val targetVideoBitrateBps = targetTotalBitrateBps - audioBitrateBps
                        maxOf(targetVideoBitrateBps.toLong(), VIDEO_BITRATE_FLOOR_BPS)
                    }
                }
                else -> {
                    // A preset applied to a source smaller than the preset's own long side
                    // does not spend the full preset bitrate on it -- the defect that made the
                    // incumbent's highest preset re-encode 4K at a fixed 3.7 Mbps
                    // (02-03-PLAN.md objective, PITFALLS.md row 13).
                    val longSideRatio =
                        effectiveLongSidePx.toDouble() / options.presetMaxLongSidePx.toDouble()
                    val fpsRatio = effectiveFps.toDouble() / NOMINAL_PRESET_FPS
                    val scaledBps =
                        options.presetVideoBitrateBps * longSideRatio * longSideRatio * fpsRatio
                    maxOf(scaledBps.toLong(), VIDEO_BITRATE_FLOOR_BPS)
                }
            }
        val inputVideoBitrateBps = input.videoBitrateBps
        if (inputVideoBitrateBps != null) {
            videoBitrateBps = minOf(videoBitrateBps, inputVideoBitrateBps)
        }

        // Transmux predicate (D-10): every condition must hold. Integer cross-multiplication
        // (`* 100` / `* 115`) for the bitrate headroom check, not floating-point multiplication
        // by 1.15, so a value placed exactly at the boundary in a test is never at the mercy of
        // binary-floating-point rounding.
        val noTrimRequested = options.trimStartMs == null && options.trimEndMs == null
        val wouldTransmux =
            input.videoCodec == VIDEO_CODEC_H264 &&
                (!input.hasAudio || input.audioCodec == AUDIO_CODEC_AAC) &&
                // AUDO-03 (04-RESEARCH.md Pitfall 1): a six-channel AAC source otherwise
                // satisfying every other condition must NOT take the remux fast path with its
                // six channels intact -- `null` (unknown) is treated as "assume safe to remux",
                // matching this file's existing unknown-input-bitrate handling, since an
                // unreadable channel count is not evidence of a 5.1 track.
                (input.audioChannelCount == null || input.audioChannelCount <= MAX_TRANSMUX_AUDIO_CHANNELS) &&
                options.audioPassthroughRequested &&
                noTrimRequested &&
                inputLongSidePx <= effectiveLongSidePx &&
                (inputFpsRounded == null || inputFpsRounded <= options.maxFps.toInt()) &&
                inputVideoBitrateBps != null &&
                inputVideoBitrateBps * 100L <= videoBitrateBps * 115L

        // Rule 7. A remux copies the same samples into a new container, so its predicted output
        // is exactly the input's own byte count rather than a bitrate*duration estimate.
        val predictedOutputBytes =
            if (wouldTransmux) {
                input.sizeBytes
            } else {
                ceil(
                    (videoBitrateBps + audioBitrateBps) * outputDurationSeconds / BITS_PER_BYTE *
                        CONTAINER_OVERHEAD_FACTOR,
                ).toLong()
            }

        // Never-larger pre-check predicate (D-11, CORE-05): decided second, only when the plan
        // is not already a remux. Equality counts as "would not help" -- a predicted output
        // exactly matching the input size gains nothing but a re-encode's generation loss.
        val wouldUseOriginal = !wouldTransmux && predictedOutputBytes >= input.sizeBytes

        return Plan(
            targetWidthPx = targetWidthPx,
            targetHeightPx = targetHeightPx,
            effectiveFps = effectiveFps,
            videoBitrateBps = videoBitrateBps,
            audioBitrateBps = audioBitrateBps,
            outputDurationMs = outputDurationMs,
            predictedOutputBytes = predictedOutputBytes,
            wouldTransmux = wouldTransmux,
            wouldUseOriginal = wouldUseOriginal,
        )
    }

    // The AAC encoder's own advertised bitrate range (`c2.android.aac.encoder`,
    // `bitrate-range = "8000-960000"`), read live on the emulator per 02-RESEARCH.md Pitfall
    // 11 -- a requested or fallback audio bitrate outside this range would either be silently
    // clamped by the codec or fail to initialise.
    private const val MIN_AUDIO_BITRATE_BPS = 8000L
    private const val MAX_AUDIO_BITRATE_BPS = 960000L
    private const val DEFAULT_AUDIO_BITRATE_BPS = 128000L

    // The emulator's software H.264 encoder's own advertised bitrate range starts at 1 bps in
    // practice, but 200000 is this project's own floor so a degenerate targetSizeMb/preset
    // combination never asks for a visually useless bitrate.
    private const val VIDEO_BITRATE_FLOOR_BPS = 200000L

    private const val NOMINAL_PRESET_FPS = 30.0
    private const val BYTES_PER_MEGABYTE = 1_000_000.0
    private const val BITS_PER_BYTE = 8.0
    private const val MILLIS_PER_SECOND = 1000.0

    // D-09's 3 percent mux overhead: a targetSizeMb request reserves this fraction of the
    // requested size for container/muxing overhead before dividing the rest between video and
    // audio bitrate.
    private const val MUX_OVERHEAD_FACTOR = 0.97

    // The inverse direction: predicting a file's size from a resolved bitrate adds back an
    // estimated 3 percent for container overhead.
    private const val CONTAINER_OVERHEAD_FACTOR = 1.03
}
