package com.danjjohnson.compress_video

import kotlin.test.Test
import kotlin.test.assertFalse
import kotlin.test.assertTrue

/**
 * Pure JVM unit tests for [TransformerEngine.resolveHevcOutputDecision] -- the coupled
 * HEVC-output-vs-keep-HDR-fallback decision [TransformerEngine.compress] and
 * [TransformerEngine.resolvePlan] both call (04-REVIEW.md CR-01/CR-02). Constructs no
 * [android.media.MediaCodecList], no file I/O, no Looper: only the five booleans the function
 * already takes, with injected capability values standing in for
 * [CodecCapabilities.hasHardwareEncoder]/`resolveKeepHdrAchievable`'s own real device probes.
 */
internal class HevcOutputDecisionTest {
    @Test
    fun plainHevcRequest_hardwareAvailable_honoursHevcWithNoFallback() {
        val decision =
            TransformerEngine.resolveHevcOutputDecision(
                requestedHevc = true,
                hasHardwareHevc = true,
                requestedKeepHdr = false,
                inputIsHdr = false,
                keepHdrAchievable = false,
            )
        assertTrue(decision.outputIsHevc)
        assertFalse(decision.hevcFallback)
    }

    @Test
    fun plainHevcRequest_noHardware_fallsBackToH264() {
        val decision =
            TransformerEngine.resolveHevcOutputDecision(
                requestedHevc = true,
                hasHardwareHevc = false,
                requestedKeepHdr = false,
                inputIsHdr = false,
                keepHdrAchievable = false,
            )
        assertFalse(decision.outputIsHevc)
        assertTrue(decision.hevcFallback)
    }

    @Test
    fun keepHdrRequest_hdrSourceAchievable_keepsHevcWithNoFallback() {
        val decision =
            TransformerEngine.resolveHevcOutputDecision(
                requestedHevc = false,
                hasHardwareHevc = false,
                requestedKeepHdr = true,
                inputIsHdr = true,
                keepHdrAchievable = true,
            )
        assertTrue(decision.outputIsHevc)
        assertFalse(decision.hevcFallback)
    }

    @Test
    fun keepHdrRequest_hdrSourceNotAchievable_fallsBackToH264() {
        val decision =
            TransformerEngine.resolveHevcOutputDecision(
                requestedHevc = false,
                hasHardwareHevc = false,
                requestedKeepHdr = true,
                inputIsHdr = true,
                keepHdrAchievable = false,
            )
        assertFalse(decision.outputIsHevc)
        assertTrue(decision.hevcFallback)
    }

    /**
     * CR-02 (04-REVIEW.md): a keep-HDR request against an already-SDR source is a harmless
     * no-op -- [resolveKeepHdrAchievable] always returns false for a non-HDR source regardless
     * of hardware, so nothing was ever attempted and nothing fell back.
     */
    @Test
    fun keepHdrRequest_sdrSource_isHarmlessNoOpNeverReportedAsFallback() {
        val decision =
            TransformerEngine.resolveHevcOutputDecision(
                requestedHevc = false,
                hasHardwareHevc = false,
                requestedKeepHdr = true,
                inputIsHdr = false,
                keepHdrAchievable = false,
            )
        assertFalse(decision.outputIsHevc)
        assertFalse(decision.hevcFallback)
    }

    /**
     * CR-01 (04-REVIEW.md), the exact reachable combination the review found: an explicit HEVC
     * request on a device with a generic hardware HEVC encoder, combined with a keep-HDR request
     * against a genuinely HDR source whose specific HDR-editing capability check fails. The
     * pre-fix formula computed `outputIsHevc = hasHardwareHevc || keepHdrAchievable = true` and
     * `hevcFallback = requestedKeepHdr && !keepHdrAchievable = true` independently, producing an
     * untagged HEVC-encoded, tone-mapped SDR file reported as a "fallback". The fix must instead
     * force H.264 whenever the keep-HDR half falls back, regardless of the independent plain-HEVC
     * capability.
     */
    @Test
    fun explicitHevcRequest_hardwareAvailable_plusUnachievableKeepHdrOnHdrSource_forcesH264Fallback() {
        val decision =
            TransformerEngine.resolveHevcOutputDecision(
                requestedHevc = true,
                hasHardwareHevc = true,
                requestedKeepHdr = true,
                inputIsHdr = true,
                keepHdrAchievable = false,
            )
        assertFalse(
            decision.outputIsHevc,
            "a keep-HDR fallback must never produce an untagged HEVC-SDR file, even when a " +
                "plain HEVC request would otherwise be honourable",
        )
        assertTrue(decision.hevcFallback)
    }

    @Test
    fun noHevcOrKeepHdrRequested_defaultsToH264WithNoFallback() {
        val decision =
            TransformerEngine.resolveHevcOutputDecision(
                requestedHevc = false,
                hasHardwareHevc = false,
                requestedKeepHdr = false,
                inputIsHdr = false,
                keepHdrAchievable = false,
            )
        assertFalse(decision.outputIsHevc)
        assertFalse(decision.hevcFallback)
    }
}
