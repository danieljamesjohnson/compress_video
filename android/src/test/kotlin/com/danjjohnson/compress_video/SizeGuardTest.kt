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
}
