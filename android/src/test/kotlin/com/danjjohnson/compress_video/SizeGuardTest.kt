package com.danjjohnson.compress_video

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

/**
 * Table-driven pure JVM tests for [SizeGuard] -- no emulator required. One named case per rule
 * and per boundary in 02-03-PLAN.md's "The resolution contract this plan implements".
 *
 * [defaultInput] mirrors `corpus/portrait_hibitrate_1080p60.mp4`'s own sidecar facts (displayed
 * 1080x1920, 60fps, ~8.76Mbps, AAC 128kbps); [defaultOptions] mirrors the `p720` preset
 * (1280 / 2,500,000) with no explicit overrides. Each test overrides only the fields its rule
 * exercises via [SizeGuard.InputInfo.copy]/[SizeGuard.Options.copy], so every hard-coded
 * expected number is traceable back to one of these two fixed baselines.
 */
internal class SizeGuardTest {
    private fun defaultInput(): SizeGuard.InputInfo =
        SizeGuard.InputInfo(
            displayedWidthPx = 1080,
            displayedHeightPx = 1920,
            rotationDegrees = 90,
            durationMs = 4000L,
            sizeBytes = 4454349L,
            videoCodec = "h264",
            videoBitrateBps = 8764164L,
            frameRateFps = 60.0,
            hasAudio = true,
            audioCodec = "aac",
            audioBitrateBps = 128000L,
        )

    private fun defaultOptions(): SizeGuard.Options =
        SizeGuard.Options(
            maxLongSidePx = null,
            videoBitrateBps = null,
            targetSizeMb = null,
            presetMaxLongSidePx = 1280L,
            presetVideoBitrateBps = 2500000L,
            maxFps = 30L,
            audioStripped = false,
            audioPassthroughRequested = true,
            requestedAudioBitrateBps = null,
            trimStartMs = null,
            trimEndMs = null,
        )

    /**
     * A qualifying baseline for [SizeGuard.Plan.wouldTransmux]: input long side exactly equal
     * to the preset's own cap, frame rate exactly at the cap, H.264+AAC, and an input video
     * bitrate comfortably inside the 1.15x headroom of the resolved (== preset, since
     * longSideRatio/fpsRatio are both 1.0) 800,000bps target. Every transmux test below flips
     * exactly one field off this baseline.
     */
    private fun transmuxInput(): SizeGuard.InputInfo =
        SizeGuard.InputInfo(
            displayedWidthPx = 640,
            displayedHeightPx = 360,
            rotationDegrees = 0,
            durationMs = 4000L,
            sizeBytes = 5_000_000L,
            videoCodec = "h264",
            videoBitrateBps = 800000L,
            frameRateFps = 30.0,
            hasAudio = true,
            audioCodec = "aac",
            audioBitrateBps = 128000L,
        )

    private fun transmuxOptions(): SizeGuard.Options =
        SizeGuard.Options(
            maxLongSidePx = null,
            videoBitrateBps = null,
            targetSizeMb = null,
            presetMaxLongSidePx = 640L,
            presetVideoBitrateBps = 800000L,
            maxFps = 30L,
            audioStripped = false,
            audioPassthroughRequested = true,
            requestedAudioBitrateBps = null,
            trimStartMs = null,
            trimEndMs = null,
        )

    @Test
    fun presetAppliedToSourceLargerThanPresetLongSide_scalesDown() {
        val plan = SizeGuard.resolve(defaultInput(), defaultOptions())
        assertEquals(720, plan.targetWidthPx)
        assertEquals(1280, plan.targetHeightPx)
        assertEquals(2500000L, plan.videoBitrateBps)
    }

    @Test
    fun presetAppliedToSourceExactlyEqualToPresetLongSide_noChangeAndBitrateScaleFactorExactlyOne() {
        val input =
            defaultInput().copy(displayedWidthPx = 720, displayedHeightPx = 1280, frameRateFps = 30.0)
        val plan = SizeGuard.resolve(input, defaultOptions())
        assertEquals(720, plan.targetWidthPx)
        assertEquals(1280, plan.targetHeightPx)
        assertEquals(2500000L, plan.videoBitrateBps)
    }

    @Test
    fun presetAppliedToSmallerSource_doesNotSpendTheFullPresetBitrate() {
        val input =
            defaultInput().copy(displayedWidthPx = 360, displayedHeightPx = 640, frameRateFps = 30.0)
        val plan = SizeGuard.resolve(input, defaultOptions())
        // No upscale: the source is already below the preset's long side.
        assertEquals(360, plan.targetWidthPx)
        assertEquals(640, plan.targetHeightPx)
        // Bitrate scales down by the square of (640 / 1280) = 0.25, not left at 2,500,000.
        assertEquals(625000L, plan.videoBitrateBps)
        assertTrue(plan.videoBitrateBps < defaultOptions().presetVideoBitrateBps)
    }

    @Test
    fun explicitLongSideOverridesThePreset_whileThePresetBitrateFormulaStillApplies() {
        val input = defaultInput().copy(frameRateFps = 30.0)
        val options = defaultOptions().copy(maxLongSidePx = 960L)
        val plan = SizeGuard.resolve(input, options)
        assertEquals(960, plan.targetHeightPx)
        assertEquals(540, plan.targetWidthPx)
        // Scaled by (960 / 1280)^2 = 0.5625 against the preset's own 2,500,000 -- the override
        // changed the target, not the preset's own reference bitrate.
        assertEquals(1406250L, plan.videoBitrateBps)
    }

    @Test
    fun explicitBitrateOverridesThePreset_whileThePresetLongSideStillApplies() {
        val input = defaultInput().copy(frameRateFps = 30.0)
        val options = defaultOptions().copy(videoBitrateBps = 1200000L)
        val plan = SizeGuard.resolve(input, options)
        assertEquals(1280, plan.targetHeightPx)
        assertEquals(1200000L, plan.videoBitrateBps)
    }

    @Test
    fun targetSizeMb_producesTheDocumentedFormulaBitrate() {
        val options = defaultOptions().copy(targetSizeMb = 2.0)
        val plan = SizeGuard.resolve(defaultInput(), options)
        // (2.0 * 1e6 * 8 / 4.0) * 0.97 - 128000 = 3,880,000 - 128,000 = 3,752,000.
        assertEquals(3752000L, plan.videoBitrateBps)
        assertEquals(128000L, plan.audioBitrateBps)
    }

    @Test
    fun targetSizeMb_soSmallThe200000Floor_binds() {
        val options = defaultOptions().copy(targetSizeMb = 0.0001)
        val plan = SizeGuard.resolve(defaultInput(), options)
        assertEquals(200000L, plan.videoBitrateBps)
    }

    @Test
    fun targetSizeMb_soLargeTheInputBitrateCap_binds() {
        val options = defaultOptions().copy(targetSizeMb = 100.0)
        val plan = SizeGuard.resolve(defaultInput(), options)
        assertEquals(8764164L, plan.videoBitrateBps)
    }

    @Test
    fun oddScalingCase_neitherOutputDimensionIsEverOdd() {
        val input = defaultInput().copy(displayedWidthPx = 853, displayedHeightPx = 1517)
        val options = defaultOptions().copy(maxLongSidePx = 641L)
        val plan = SizeGuard.resolve(input, options)
        assertEquals(0, plan.targetWidthPx % 2)
        assertEquals(0, plan.targetHeightPx % 2)
        assertTrue(plan.targetHeightPx <= 641)
        assertTrue(plan.targetWidthPx <= 641)
    }

    @Test
    fun maxLongSidePxOfExactly16_acceptedAndTheShortSideFloorsAt16() {
        val input = defaultInput().copy(displayedWidthPx = 1920, displayedHeightPx = 100)
        val options = defaultOptions().copy(maxLongSidePx = 16L)
        val plan = SizeGuard.resolve(input, options)
        assertEquals(16, plan.targetWidthPx)
        // Naive scaling would give 100 * (16/1920) ~= 0.83, rounded down and evened to 0 --
        // the 16px floor prevents a zero or sub-minimum short side reaching the encoder.
        assertEquals(16, plan.targetHeightPx)
    }

    @Test
    fun fps60InputAtMaxFps30_effectiveFpsIs30() {
        val plan = SizeGuard.resolve(defaultInput(), defaultOptions())
        assertEquals(30, plan.effectiveFps)
    }

    @Test
    fun fps30InputAtMaxFps60_effectiveFpsIs30NotUpscaled() {
        val input = defaultInput().copy(frameRateFps = 30.0)
        val options = defaultOptions().copy(maxFps = 60L)
        val plan = SizeGuard.resolve(input, options)
        assertEquals(30, plan.effectiveFps)
    }

    @Test
    fun fps29p97InputAtMaxFps30_effectiveFpsIs30_provingHalfUpRounding() {
        val input = defaultInput().copy(frameRateFps = 29.97)
        val plan = SizeGuard.resolve(input, defaultOptions())
        // A truncating (non-half-up) rounder would give 29, and min(30, 29) = 29 -- wrong.
        assertEquals(30, plan.effectiveFps)
    }

    @Test
    fun unknownInputFrameRate_fallsBackToMaxFpsUnchanged() {
        val input = defaultInput().copy(frameRateFps = null)
        val options = defaultOptions().copy(maxFps = 24L)
        val plan = SizeGuard.resolve(input, options)
        assertEquals(24, plan.effectiveFps)
    }

    @Test
    fun unknownInputVideoBitrate_noCapApplied_computedBitrateStands() {
        val input = defaultInput().copy(videoBitrateBps = null, frameRateFps = 30.0)
        val plan = SizeGuard.resolve(input, defaultOptions())
        assertEquals(2500000L, plan.videoBitrateBps)
    }

    @Test
    fun strippedAudio_bitrateZero_excludedFromTargetSizeSubtraction() {
        val options = defaultOptions().copy(targetSizeMb = 2.0, audioStripped = true)
        val plan = SizeGuard.resolve(defaultInput(), options)
        assertEquals(0L, plan.audioBitrateBps)
        // No audio subtraction: (2.0 * 1e6 * 8 / 4.0) * 0.97 = 3,880,000, unlike the
        // audio-present case (3,752,000) proven in targetSizeMb_producesTheDocumentedFormulaBitrate.
        assertEquals(3880000L, plan.videoBitrateBps)
    }

    @Test
    fun requestedAudioBitrateInsideTheRange_passesThroughUnchanged() {
        val options = defaultOptions().copy(requestedAudioBitrateBps = 64000L)
        val plan = SizeGuard.resolve(defaultInput(), options)
        assertEquals(64000L, plan.audioBitrateBps)
    }

    @Test
    fun noRequestedAudioBitrate_fallsBackToTheSourceSOwnAudioBitrate() {
        // defaultInput().audioBitrateBps is 128000L; requestedAudioBitrateBps is null in
        // defaultOptions(), so rule 5's fallback chain (request, then source, then the
        // 128,000bps project default) resolves to the source's own value here -- which happens
        // to equal the same project default, so this case also overrides the source value to
        // something else to prove the fallback is really reading the source, not coincidentally
        // landing on the same default either way.
        val input = defaultInput().copy(audioBitrateBps = 96000L)
        val plan = SizeGuard.resolve(input, defaultOptions())
        assertEquals(96000L, plan.audioBitrateBps)
    }

    @Test
    fun requestedAudioBitrateBelow8000_clampedUpToTheFloor() {
        val options = defaultOptions().copy(requestedAudioBitrateBps = 100L)
        val plan = SizeGuard.resolve(defaultInput(), options)
        assertEquals(8000L, plan.audioBitrateBps)
    }

    @Test
    fun requestedAudioBitrateAbove960000_clampedDownToTheCeiling() {
        val options = defaultOptions().copy(requestedAudioBitrateBps = 2000000L)
        val plan = SizeGuard.resolve(defaultInput(), options)
        assertEquals(960000L, plan.audioBitrateBps)
    }

    @Test
    fun trimmedRequest_usesTheTrimmedDurationForTargetSizeBitrateAndPredictedBytes() {
        val options =
            defaultOptions().copy(trimStartMs = 1000L, trimEndMs = 3000L, targetSizeMb = 1.0)
        val plan = SizeGuard.resolve(defaultInput(), options)
        assertEquals(2000L, plan.outputDurationMs)
        // (1.0 * 1e6 * 8 / 2.0) * 0.97 - 128000 = 3,880,000 - 128,000 = 3,752,000.
        assertEquals(3752000L, plan.videoBitrateBps)
        // ((3,752,000 + 128,000) * 2.0 / 8) * 1.03 = 970,000 * 1.03 = 999,100.
        assertEquals(999100L, plan.predictedOutputBytes)
    }

    @Test
    fun resolve_isPure_twoDifferentOptionsAgainstTheSameInputDoNotContaminateEachOther() {
        val input = defaultInput()
        val p360 = defaultOptions().copy(presetMaxLongSidePx = 640L, presetVideoBitrateBps = 800000L)
        val p720 = defaultOptions()

        val p360Plan = SizeGuard.resolve(input, p360)
        val p720Plan = SizeGuard.resolve(input, p720)

        assertEquals(640, p360Plan.targetHeightPx)
        assertEquals(800000L, p360Plan.videoBitrateBps)
        assertEquals(1280, p720Plan.targetHeightPx)
        assertEquals(2500000L, p720Plan.videoBitrateBps)
    }

    // --- wouldUseOriginal (D-11, CORE-05, plan 02-04 task 1) ---
    //
    // defaultInput()/defaultOptions() (1080x1920, preset cap 1280) never qualifies for
    // transmux -- the preset's own long side is below the input's -- so these cases isolate
    // the never-larger predicate from the transmux one. targetSizeMb=1.0 against the default
    // 4-second/128kbps-audio baseline resolves to a known, exact predictedOutputBytes of
    // 999,100 (same arithmetic as targetSizeMb_producesTheDocumentedFormulaBitrate, halved for
    // a 1.0MB target instead of 2.0MB), so sizeBytes is placed directly at, above, and below
    // that boundary rather than re-deriving the bitrate math per case.

    @Test
    fun wouldUseOriginal_predictedOutputAboveInputSize_setsTheFlag() {
        val options = defaultOptions().copy(targetSizeMb = 1.0)
        val input = defaultInput().copy(sizeBytes = 999_099L)
        val plan = SizeGuard.resolve(input, options)
        assertEquals(999_100L, plan.predictedOutputBytes)
        assertTrue(plan.wouldUseOriginal)
    }

    @Test
    fun wouldUseOriginal_predictedOutputExactlyEqualToInputSize_setsTheFlag() {
        val options = defaultOptions().copy(targetSizeMb = 1.0)
        val input = defaultInput().copy(sizeBytes = 999_100L)
        val plan = SizeGuard.resolve(input, options)
        assertTrue(
            plan.wouldUseOriginal,
            "equality counts as 'would not help' -- CORE-05's flagged assumption",
        )
    }

    @Test
    fun wouldUseOriginal_predictedOutputOneByteBelowInputSize_doesNotSetTheFlag() {
        val options = defaultOptions().copy(targetSizeMb = 1.0)
        val input = defaultInput().copy(sizeBytes = 999_101L)
        val plan = SizeGuard.resolve(input, options)
        assertTrue(!plan.wouldUseOriginal)
    }

    @Test
    fun wouldUseOriginal_neverSetWhenThePlanIsARemux() {
        // The qualifying transmux baseline predicts output bytes exactly equal to the input's
        // own size (a remux copies the same samples) -- which would trip the equality rule
        // above if wouldTransmux did not take precedence. It must not.
        val plan = SizeGuard.resolve(transmuxInput(), transmuxOptions())
        assertTrue(plan.wouldTransmux)
        assertEquals(plan.predictedOutputBytes, transmuxInput().sizeBytes)
        assertTrue(!plan.wouldUseOriginal)
    }

    // --- wouldTransmux (D-10, plan 02-04 task 2) ---
    //
    // transmuxInput()/transmuxOptions() is a baseline every one of the seven conditions
    // satisfies. Each case below flips exactly one field off that baseline.

    @Test
    fun wouldTransmux_qualifyingBaseline_isTrue() {
        val plan = SizeGuard.resolve(transmuxInput(), transmuxOptions())
        assertTrue(plan.wouldTransmux)
    }

    @Test
    fun wouldTransmux_nonH264VideoCodec_disqualifies() {
        val input = transmuxInput().copy(videoCodec = "hevc")
        val plan = SizeGuard.resolve(input, transmuxOptions())
        assertTrue(!plan.wouldTransmux)
    }

    @Test
    fun wouldTransmux_nonAacAudioCodec_disqualifies() {
        val input = transmuxInput().copy(audioCodec = "opus")
        val plan = SizeGuard.resolve(input, transmuxOptions())
        assertTrue(!plan.wouldTransmux)
    }

    @Test
    fun wouldTransmux_forcedAudioReencode_disqualifies() {
        val options = transmuxOptions().copy(audioPassthroughRequested = false)
        val plan = SizeGuard.resolve(transmuxInput(), options)
        assertTrue(!plan.wouldTransmux)
    }

    @Test
    fun wouldTransmux_audioStrip_disqualifies() {
        val options =
            transmuxOptions().copy(audioStripped = true, audioPassthroughRequested = false)
        val plan = SizeGuard.resolve(transmuxInput(), options)
        assertTrue(!plan.wouldTransmux)
    }

    @Test
    fun wouldTransmux_trimRequested_disqualifies() {
        val options = transmuxOptions().copy(trimStartMs = 500L)
        val plan = SizeGuard.resolve(transmuxInput(), options)
        assertTrue(!plan.wouldTransmux)
    }

    @Test
    fun wouldTransmux_longSideOnePixelAboveTheTarget_disqualifies() {
        val input = transmuxInput().copy(displayedWidthPx = 641)
        val plan = SizeGuard.resolve(input, transmuxOptions())
        assertTrue(!plan.wouldTransmux)
    }

    @Test
    fun wouldTransmux_frameRateOneAboveTheCap_disqualifies() {
        val input = transmuxInput().copy(frameRateFps = 31.0)
        val plan = SizeGuard.resolve(input, transmuxOptions())
        assertTrue(!plan.wouldTransmux)
    }

    @Test
    fun wouldTransmux_bitrateExactlyAt1point15TimesTheTarget_qualifies() {
        // Resolved video bitrate stays 800,000 (min against a raised input bitrate that is
        // still above the preset-scaled value), so 920,000 is exactly the 1.15x boundary.
        val input = transmuxInput().copy(videoBitrateBps = 920_000L)
        val plan = SizeGuard.resolve(input, transmuxOptions())
        assertEquals(800_000L, plan.videoBitrateBps)
        assertTrue(plan.wouldTransmux)
    }

    @Test
    fun wouldTransmux_bitrateOneBpsAboveTheHeadroom_disqualifies() {
        val input = transmuxInput().copy(videoBitrateBps = 920_001L)
        val plan = SizeGuard.resolve(input, transmuxOptions())
        assertEquals(800_000L, plan.videoBitrateBps)
        assertTrue(!plan.wouldTransmux)
    }

    @Test
    fun wouldTransmux_unknownInputBitrate_disqualifies() {
        val input = transmuxInput().copy(videoBitrateBps = null)
        val plan = SizeGuard.resolve(input, transmuxOptions())
        assertTrue(!plan.wouldTransmux)
    }

    @Test
    fun wouldTransmux_noAudioInputWithEverythingElseQualifying_qualifies() {
        val input = transmuxInput().copy(hasAudio = false, audioCodec = null)
        val plan = SizeGuard.resolve(input, transmuxOptions())
        assertTrue(plan.wouldTransmux)
    }
}
