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
 * Implements the seven-rule resolution contract in 02-03-PLAN.md exactly, in order. The
 * transmux and never-larger predicates that also conceptually live on this function are added
 * in plan 02-04; this object only resolves target size, frame rate and bitrate.
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
    )

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
        /** Predicted output file size, in bytes, including estimated container overhead. */
        val predictedOutputBytes: Long,
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
                    val targetTotalBitrateBps =
                        options.targetSizeMb * BYTES_PER_MEGABYTE * BITS_PER_BYTE /
                            outputDurationSeconds * MUX_OVERHEAD_FACTOR
                    val targetVideoBitrateBps = targetTotalBitrateBps - audioBitrateBps
                    maxOf(targetVideoBitrateBps.toLong(), VIDEO_BITRATE_FLOOR_BPS)
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

        // Rule 7.
        val predictedOutputBytes =
            ceil(
                (videoBitrateBps + audioBitrateBps) * outputDurationSeconds / BITS_PER_BYTE *
                    CONTAINER_OVERHEAD_FACTOR,
            ).toLong()

        return Plan(
            targetWidthPx = targetWidthPx,
            targetHeightPx = targetHeightPx,
            effectiveFps = effectiveFps,
            videoBitrateBps = videoBitrateBps,
            audioBitrateBps = audioBitrateBps,
            outputDurationMs = outputDurationMs,
            predictedOutputBytes = predictedOutputBytes,
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
