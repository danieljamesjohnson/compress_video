package com.danjjohnson.compress_video

import androidx.media3.effect.FrameDropEffect
import androidx.media3.effect.Presentation
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

/**
 * Pure JVM unit tests for [TransformerEngine.buildVideoEffects] -- the pinned, documented order
 * of the video effects list (geometry first, frame selection second, 02-05-PLAN.md task 2).
 * Constructs no [androidx.media3.transformer.Transformer] and touches no Looper: only the two
 * effect objects themselves and the plain-data [SizeGuard.Plan] this function already takes.
 */
internal class EffectOrderTest {
    /**
     * A [SizeGuard.Plan] with every field the tests below don't care about held at an arbitrary
     * fixed value -- only [targetWidthPx]/[targetHeightPx]/[effectiveFps] vary per case.
     */
    private fun planWith(
        targetWidthPx: Int = 720,
        targetHeightPx: Int = 1280,
        effectiveFps: Int = 30,
    ): SizeGuard.Plan =
        SizeGuard.Plan(
            targetWidthPx = targetWidthPx,
            targetHeightPx = targetHeightPx,
            effectiveFps = effectiveFps,
            videoBitrateBps = 2_500_000L,
            audioBitrateBps = 128_000L,
            outputDurationMs = 4000L,
            predictedOutputBytes = 1_000_000L,
            wouldTransmux = false,
            wouldUseOriginal = false,
        )

    @Test
    fun bothEffectsApply_geometryIsFirstAndFrameSelectionIsSecond() {
        val effects =
            TransformerEngine.buildVideoEffects(
                target = planWith(targetWidthPx = 720, targetHeightPx = 1280, effectiveFps = 30),
                inputDisplayedWidthPx = 1080,
                inputDisplayedHeightPx = 1920,
                inputFps = 60.0,
            )
        assertEquals(2, effects.size)
        assertTrue(effects[0] is Presentation, "geometry must be built before frame selection")
        assertTrue(effects[1] is FrameDropEffect)
    }

    @Test
    fun onlyGeometryApplies_theListHasExactlyOneEntry() {
        val effects =
            TransformerEngine.buildVideoEffects(
                target = planWith(targetWidthPx = 720, targetHeightPx = 1280, effectiveFps = 30),
                inputDisplayedWidthPx = 1080,
                inputDisplayedHeightPx = 1920,
                inputFps = 30.0,
            )
        assertEquals(1, effects.size)
        assertTrue(effects[0] is Presentation)
    }

    @Test
    fun onlyFrameSelectionApplies_theListHasExactlyOneEntry() {
        val effects =
            TransformerEngine.buildVideoEffects(
                target = planWith(targetWidthPx = 1080, targetHeightPx = 1920, effectiveFps = 30),
                inputDisplayedWidthPx = 1080,
                inputDisplayedHeightPx = 1920,
                inputFps = 60.0,
            )
        assertEquals(1, effects.size)
        assertTrue(effects[0] is FrameDropEffect)
    }

    @Test
    fun neitherEffectApplies_theListIsEmpty() {
        val effects =
            TransformerEngine.buildVideoEffects(
                target = planWith(targetWidthPx = 1080, targetHeightPx = 1920, effectiveFps = 30),
                inputDisplayedWidthPx = 1080,
                inputDisplayedHeightPx = 1920,
                inputFps = 30.0,
            )
        assertTrue(effects.isEmpty())
    }
}
