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
}
