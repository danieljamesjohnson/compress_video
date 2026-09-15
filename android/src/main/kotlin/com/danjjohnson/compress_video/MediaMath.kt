package com.danjjohnson.compress_video

import kotlin.math.floor
import kotlin.math.roundToInt

/**
 * Pure, unit-testable rotation/dimension/codec/duration logic shared by every Android call.
 *
 * No Android framework imports beyond constants -- every function here must be exercisable as
 * plain JVM code with no emulator, which is what [MediaMathTest] does.
 */
object MediaMath {
    /**
     * Returns the displayed (rotation-corrected) `(width, height)` pair for a video whose
     * coded dimensions are `codedWidthPx x codedHeightPx` and whose unsigned clockwise
     * rotation is `rotationDegrees`.
     *
     * Swaps width/height for 90 and 270; passes both through unchanged for 0 and 180. The two
     * cases are decided by separate branches over the rotation value, so a clip whose coded
     * width and height happen to be equal is still reported with the correct rotation instead
     * of the swap silently becoming a no-op.
     */
    fun displayedSize(
        codedWidthPx: Int,
        codedHeightPx: Int,
        rotationDegrees: Int,
    ): Pair<Int, Int> =
        when (rotationDegrees) {
            90, 270 -> Pair(codedHeightPx, codedWidthPx)
            else -> Pair(codedWidthPx, codedHeightPx)
        }

    /**
     * Normalises a platform-reported MIME type or FourCC into one of the wire-contract codec
     * tokens: `h264`, `hevc`, `av1`, `vp9`, `unknown`. `null` input, and any value this
     * function does not recognise, both map to `unknown` -- never an exception.
     */
    fun normalizeCodec(mimeOrFourCc: String?): String {
        if (mimeOrFourCc == null) return "unknown"
        return when (mimeOrFourCc.lowercase()) {
            "video/avc", "avc1", "h264" -> "h264"
            "video/hevc", "hvc1", "hev1", "h265", "hevc" -> "hevc"
            "video/av01", "av01", "av1" -> "av1"
            "video/x-vnd.on2.vp9", "vp09", "vp9" -> "vp9"
            else -> "unknown"
        }
    }

    /**
     * Rounds a millisecond duration value half-up: `.5` rounds away from zero (`4000.5` ->
     * `4001`), `.4` rounds down (`4000.4` -> `4000`). Used when a platform reports duration in
     * a unit that requires conversion to whole milliseconds.
     */
    fun roundHalfUpMs(valueMs: Double): Long = floor(valueMs + 0.5).toLong()

    /**
     * Returns the `(width, height)` a displayed `displayedWidthPx x displayedHeightPx` frame
     * should be scaled to so its longer side is at most `maxDimensionPx`, preserving aspect
     * ratio and rounding to the nearest integer.
     *
     * Returns the input unchanged -- never a larger dimension than the input -- when
     * `maxDimensionPx` is `null` or already at least the longer of the two input sides. This
     * is what guarantees a thumbnail is never upscaled.
     */
    fun scaledSize(
        displayedWidthPx: Int,
        displayedHeightPx: Int,
        maxDimensionPx: Int?,
    ): Pair<Int, Int> {
        if (maxDimensionPx == null) {
            return Pair(displayedWidthPx, displayedHeightPx)
        }
        val longerSidePx = maxOf(displayedWidthPx, displayedHeightPx)
        if (maxDimensionPx >= longerSidePx) {
            return Pair(displayedWidthPx, displayedHeightPx)
        }
        val scale = maxDimensionPx.toDouble() / longerSidePx.toDouble()
        val scaledWidthPx = (displayedWidthPx * scale).roundToInt().coerceAtLeast(1)
        val scaledHeightPx = (displayedHeightPx * scale).roundToInt().coerceAtLeast(1)
        return Pair(scaledWidthPx, scaledHeightPx)
    }

    /**
     * Clamps a requested `positionMs` to `durationMs`: a value above `durationMs` clamps down
     * to it, and `positionMs == durationMs` passes through unchanged so the last frame is still
     * returned, not an error. A negative `positionMs` is never seen here -- [Arguments] rejects
     * it before this is ever called -- so this function does not special-case it.
     */
    fun clampPositionMs(
        positionMs: Long,
        durationMs: Long,
    ): Long = if (positionMs > durationMs) durationMs else positionMs
}
