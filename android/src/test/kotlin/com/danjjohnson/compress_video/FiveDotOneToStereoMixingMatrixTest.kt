package com.danjjohnson.compress_video

import kotlin.test.Test
import kotlin.test.assertEquals

/**
 * Pure JVM unit tests for [TransformerEngine.fiveDotOneToStereoMixingMatrix] -- the fixed
 * 5.1-to-stereo downmix coefficients AUDO-03's forced re-encode uses (WR-01, 04-REVIEW.md: this
 * matrix was previously untested even at the unit level, and the corpus fixture that exercises
 * it end to end carried identical audio content on all six channels, making it structurally
 * incapable of catching a channel-index transposition). Constructs no `Transformer`, no `File`,
 * no Looper: only the coefficient matrix itself, read via
 * `ChannelMixingMatrix.getMixingCoefficient(inputChannelIndex, outputChannelIndex)`.
 *
 * Channel indices follow `AudioFormat.CHANNEL_OUT_5POINT1`: 0=FL, 1=FR, 2=FC, 3=LFE, 4=BL, 5=BR.
 * Output indices: 0=L, 1=R.
 */
internal class FiveDotOneToStereoMixingMatrixTest {
    private val matrix = TransformerEngine.fiveDotOneToStereoMixingMatrix()

    private fun coefficient(
        inputChannel: Int,
        outputChannel: Int,
    ): Float = matrix.getMixingCoefficient(inputChannel, outputChannel)

    @Test
    fun frontLeft_passesStraightThroughToLeftOnly() {
        assertEquals(1f, coefficient(inputChannel = 0, outputChannel = 0))
        assertEquals(0f, coefficient(inputChannel = 0, outputChannel = 1))
    }

    @Test
    fun frontRight_passesStraightThroughToRightOnly() {
        assertEquals(0f, coefficient(inputChannel = 1, outputChannel = 0))
        assertEquals(1f, coefficient(inputChannel = 1, outputChannel = 1))
    }

    @Test
    fun centre_foldsIntoBothSidesAtTheDocumentedGain() {
        assertEquals(SURROUND_DOWNMIX_GAIN_FOR_TEST, coefficient(inputChannel = 2, outputChannel = 0))
        assertEquals(SURROUND_DOWNMIX_GAIN_FOR_TEST, coefficient(inputChannel = 2, outputChannel = 1))
    }

    @Test
    fun lfe_isNotFoldedIntoEitherSide() {
        assertEquals(0f, coefficient(inputChannel = 3, outputChannel = 0))
        assertEquals(0f, coefficient(inputChannel = 3, outputChannel = 1))
    }

    /**
     * The regression WR-01 exists to catch: back-left must fold into L ONLY, never R. A
     * channel-index transposition between back-left and back-right (or a copy-paste swap of
     * their coefficient rows) would flip this exact assertion.
     */
    @Test
    fun backLeft_foldsIntoLeftOnlyNeverRight() {
        assertEquals(SURROUND_DOWNMIX_GAIN_FOR_TEST, coefficient(inputChannel = 4, outputChannel = 0))
        assertEquals(0f, coefficient(inputChannel = 4, outputChannel = 1))
    }

    /**
     * The regression WR-01 exists to catch, mirrored: back-right must fold into R ONLY, never L.
     */
    @Test
    fun backRight_foldsIntoRightOnlyNeverLeft() {
        assertEquals(0f, coefficient(inputChannel = 5, outputChannel = 0))
        assertEquals(SURROUND_DOWNMIX_GAIN_FOR_TEST, coefficient(inputChannel = 5, outputChannel = 1))
    }

    private companion object {
        // Mirrors TransformerEngine's own private SURROUND_DOWNMIX_GAIN constant (IN-01, out of
        // this fix pass's scope) -- duplicated here rather than exposed, since this test cares
        // about the matrix's documented -3dB fold-in gain, whatever its exact literal is, not
        // about coupling to that private implementation constant.
        private const val SURROUND_DOWNMIX_GAIN_FOR_TEST = 0.7071068f
    }
}
