package com.danjjohnson.compress_video

import kotlin.test.Test
import kotlin.test.assertEquals

/**
 * Pure JVM tests for [MediaMath] -- no emulator required.
 */
internal class MediaMathTest {
    @Test
    fun displayedSize_rotation0_passesThroughUnchanged() {
        assertEquals(Pair(1920, 1080), MediaMath.displayedSize(1920, 1080, 0))
    }

    @Test
    fun displayedSize_rotation90_swapsWidthAndHeight() {
        assertEquals(Pair(1080, 1920), MediaMath.displayedSize(1920, 1080, 90))
    }

    @Test
    fun displayedSize_rotation180_passesThroughUnchanged() {
        assertEquals(Pair(1920, 1080), MediaMath.displayedSize(1920, 1080, 180))
    }

    @Test
    fun displayedSize_rotation270_swapsWidthAndHeight() {
        assertEquals(Pair(1080, 1920), MediaMath.displayedSize(1920, 1080, 270))
    }

    @Test
    fun displayedSize_squareCodedFrame_stillDecidesByRotationBranch() {
        // Coded width == coded height can't show a numeric difference between the swapped and
        // unswapped result, but this pins that the function still takes the rotation branch
        // (rather than short-circuiting on "width == height") for both a rotated and an
        // unrotated square input.
        assertEquals(Pair(1080, 1080), MediaMath.displayedSize(1080, 1080, 90))
        assertEquals(Pair(1080, 1080), MediaMath.displayedSize(1080, 1080, 0))
    }

    @Test
    fun normalizeCodec_mapsKnownAndroidMimeTypes() {
        assertEquals("h264", MediaMath.normalizeCodec("video/avc"))
        assertEquals("hevc", MediaMath.normalizeCodec("video/hevc"))
        assertEquals("av1", MediaMath.normalizeCodec("video/av01"))
        assertEquals("vp9", MediaMath.normalizeCodec("video/x-vnd.on2.vp9"))
    }

    @Test
    fun normalizeCodec_mapsAppleFourCcToTheSameToken() {
        // Android's video/avc and Apple's avc1 both normalise to h264 -- the cross-platform
        // contract this function exists to guarantee.
        assertEquals("h264", MediaMath.normalizeCodec("avc1"))
    }

    @Test
    fun normalizeCodec_unknownMimeMapsToUnknown() {
        assertEquals("unknown", MediaMath.normalizeCodec("video/mpeg2"))
    }

    @Test
    fun normalizeCodec_nullMapsToUnknown() {
        assertEquals("unknown", MediaMath.normalizeCodec(null))
    }

    @Test
    fun roundHalfUpMs_roundsDownBelowTheHalfBoundary() {
        assertEquals(4000L, MediaMath.roundHalfUpMs(4000.4))
    }

    @Test
    fun roundHalfUpMs_roundsUpAtTheHalfBoundary() {
        assertEquals(4001L, MediaMath.roundHalfUpMs(4000.5))
    }

    @Test
    fun scaledSize_maxDimensionEqualToTheLongerSide_returnsInputUnchanged() {
        // 1080x1920 is portrait_rot90.mp4's displayed size (corpus/portrait_rot90.expected.json).
        assertEquals(Pair(1080, 1920), MediaMath.scaledSize(1080, 1920, 1920))
    }

    @Test
    fun scaledSize_maxDimensionOnePixelBelowTheLongerSide_downscalesPreservingAspectRatio() {
        val (widthPx, heightPx) = MediaMath.scaledSize(1080, 1920, 1919)
        assertEquals(1919, heightPx)
        assertEquals(1079, widthPx)
    }

    @Test
    fun scaledSize_maxDimensionFarAboveTheLongerSide_neverUpscales() {
        assertEquals(Pair(1080, 1920), MediaMath.scaledSize(1080, 1920, 4000))
    }

    @Test
    fun scaledSize_nullMaxDimension_returnsInputUnchanged() {
        assertEquals(Pair(1080, 1920), MediaMath.scaledSize(1080, 1920, null))
    }

    @Test
    fun scaledSize_squareInput_capsBothSidesEqually() {
        assertEquals(Pair(500, 500), MediaMath.scaledSize(1000, 1000, 500))
    }

    @Test
    fun clampPositionMs_belowDuration_passesThroughUnchanged() {
        assertEquals(3999L, MediaMath.clampPositionMs(3999L, 4000L))
    }

    @Test
    fun clampPositionMs_exactlyAtDuration_passesThroughUnchanged() {
        assertEquals(4000L, MediaMath.clampPositionMs(4000L, 4000L))
    }

    @Test
    fun clampPositionMs_aboveDuration_clampsDownToDuration() {
        assertEquals(4000L, MediaMath.clampPositionMs(4001L, 4000L))
    }

    @Test
    fun floorToEvenMin16_exactlyEvenInput_passesThroughUnchanged() {
        assertEquals(720, MediaMath.floorToEvenMin16(720.0))
    }

    @Test
    fun floorToEvenMin16_oddInput_roundsDownToTheEvenBelow() {
        assertEquals(718, MediaMath.floorToEvenMin16(719.9))
        // An exact odd integer must also round down, not just a fractional odd-adjacent value.
        assertEquals(718, MediaMath.floorToEvenMin16(719.0))
    }

    @Test
    fun floorToEvenMin16_belowTheFloor_clampsUpTo16() {
        assertEquals(16, MediaMath.floorToEvenMin16(10.0))
        // An odd value below the floor must still land on 16, not on 15 or 14.
        assertEquals(16, MediaMath.floorToEvenMin16(15.0))
    }

    @Test
    fun roundFpsHalfUp_belowTheHalfBoundary_roundsDown() {
        assertEquals(29, MediaMath.roundFpsHalfUp(29.4))
    }

    @Test
    fun roundFpsHalfUp_exactlyAtTheHalfBoundary_roundsUp() {
        assertEquals(30, MediaMath.roundFpsHalfUp(29.5))
    }

    @Test
    fun roundFpsHalfUp_ntscFrameRate_roundsUpTo30() {
        // 29.97 fps (NTSC) must count as 30 when compared against an integer maxFps cap.
        assertEquals(30, MediaMath.roundFpsHalfUp(29.97))
    }
}
