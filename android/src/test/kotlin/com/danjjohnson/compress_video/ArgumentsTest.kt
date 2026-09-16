package com.danjjohnson.compress_video

import java.io.File
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertTrue

/**
 * Pure JVM tests for [Arguments] -- no emulator required.
 */
internal class ArgumentsTest {
    @Test
    fun requireReadableMediaFile_blankPath_rejectedAsUnsupportedInput() {
        val error =
            assertFailsWith<CompressVideoError> {
                Arguments.requireReadableMediaFile("   ")
            }
        assertEquals("unsupportedInput", error.code)
    }

    @Test
    fun requireReadableMediaFile_missingFile_rejectedAsFileNotFound() {
        val error =
            assertFailsWith<CompressVideoError> {
                Arguments.requireReadableMediaFile(
                    "/tmp/compress_video_arguments_test_does_not_exist_12345.mp4",
                )
            }
        assertEquals("fileNotFound", error.code)
    }

    @Test
    fun requireReadableMediaFile_emptyFile_rejectedAsUnsupportedInput() {
        val tempFile = File.createTempFile("compress_video_arguments_test_", ".mp4")
        tempFile.deleteOnExit()
        try {
            val error =
                assertFailsWith<CompressVideoError> {
                    Arguments.requireReadableMediaFile(tempFile.path)
                }
            assertEquals("unsupportedInput", error.code)
        } finally {
            tempFile.delete()
        }
    }

    @Test
    fun requireReadableMediaFile_realFile_returnsItsCanonicalForm() {
        val tempFile = File.createTempFile("compress_video_arguments_test_", ".mp4")
        tempFile.deleteOnExit()
        try {
            tempFile.writeBytes(byteArrayOf(1, 2, 3))
            val result = Arguments.requireReadableMediaFile(tempFile.path)
            assertEquals(tempFile.canonicalFile, result)
            assertTrue(result.canRead())
        } finally {
            tempFile.delete()
        }
    }

    @Test
    fun requireWritableOutputParent_missingParentDirectory_rejectedAsIo() {
        val tempDir = File.createTempFile("compress_video_arguments_test_", "").also {
            it.delete()
            it.mkdirs()
        }
        tempDir.deleteOnExit()
        try {
            val error =
                assertFailsWith<CompressVideoError> {
                    Arguments.requireWritableOutputParent(
                        "${tempDir.path}/does_not_exist_dir/thumb.jpg",
                    )
                }
            assertEquals("io", error.code)
        } finally {
            tempDir.delete()
        }
    }

    @Test
    fun requireWritableOutputParent_existingWritableParent_returnsCanonicalPath() {
        val tempDir = File.createTempFile("compress_video_arguments_test_", "").also {
            it.delete()
            it.mkdirs()
        }
        tempDir.deleteOnExit()
        try {
            val target = File(tempDir, "thumb.jpg")
            val result = Arguments.requireWritableOutputParent(target.path)
            assertEquals(target.canonicalFile, result)
        } finally {
            tempDir.delete()
        }
    }

    @Test
    fun validatePositionMs_negative_rejectedAsUnsupportedInput() {
        assertEquals("unsupportedInput", Arguments.validatePositionMs(-1L))
    }

    @Test
    fun validatePositionMs_zeroOrPositive_isValid() {
        assertEquals(null, Arguments.validatePositionMs(0L))
        assertEquals(null, Arguments.validatePositionMs(1500L))
    }

    @Test
    fun validateQuality_belowOne_rejectedAsUnsupportedInput() {
        assertEquals("unsupportedInput", Arguments.validateQuality(0L))
    }

    @Test
    fun validateQuality_above100_rejectedAsUnsupportedInput() {
        assertEquals("unsupportedInput", Arguments.validateQuality(101L))
    }

    @Test
    fun validateQuality_withinRange_isValid() {
        assertEquals(null, Arguments.validateQuality(1L))
        assertEquals(null, Arguments.validateQuality(100L))
    }

    @Test
    fun validateMaxDimensionPx_nonPositive_rejectedAsUnsupportedInput() {
        assertEquals("unsupportedInput", Arguments.validateMaxDimensionPx(0L))
        assertEquals("unsupportedInput", Arguments.validateMaxDimensionPx(-100L))
    }

    @Test
    fun validateMaxDimensionPx_nullOrPositive_isValid() {
        assertEquals(null, Arguments.validateMaxDimensionPx(null))
        assertEquals(null, Arguments.validateMaxDimensionPx(1L))
    }

    @Test
    fun validateOutputPath_blank_rejectedAsUnsupportedInput() {
        assertEquals("unsupportedInput", Arguments.validateOutputPath("   "))
    }

    @Test
    fun validateOutputPath_nullOrNonBlank_isValid() {
        assertEquals(null, Arguments.validateOutputPath(null))
        assertEquals(null, Arguments.validateOutputPath("/tmp/thumb.jpg"))
    }

    @Test
    fun requireValidThumbnailArgs_allValid_doesNotThrow() {
        Arguments.requireValidThumbnailArgs(1500L, 80L, 1920L, "/tmp/thumb.jpg")
        Arguments.requireValidThumbnailArgs(0L, 1L, null, null)
    }

    @Test
    fun requireValidThumbnailArgs_negativePositionMs_throwsWithThatReason() {
        val error =
            assertFailsWith<CompressVideoError> {
                Arguments.requireValidThumbnailArgs(-1L, 80L, null, null)
            }
        assertEquals("unsupportedInput", error.code)
    }

    private fun validCompressRequest(): CompressRequestMessage =
        CompressRequestMessage(
            maxLongSidePx = null,
            videoBitrateBps = null,
            targetSizeMb = null,
            presetMaxLongSidePx = 1280L,
            presetVideoBitrateBps = 2500000L,
            maxFps = 30L,
            audioMode = AudioModeMessage.PASSTHROUGH,
            audioBitrateBps = null,
            audioChannels = null,
            trimStartMs = null,
            trimEndMs = null,
            outputPath = null,
            videoCodec = "h264",
            hdrMode = "toneMapToSdr",
        )

    @Test
    fun validateMaxFps_nonPositive_rejectedAsUnsupportedInput() {
        assertEquals("unsupportedInput", Arguments.validateMaxFps(0L))
        assertEquals("unsupportedInput", Arguments.validateMaxFps(-1L))
    }

    @Test
    fun validateMaxFps_positive_isValid() {
        assertEquals(null, Arguments.validateMaxFps(1L))
        assertEquals(null, Arguments.validateMaxFps(30L))
    }

    @Test
    fun validateMaxLongSidePx_below16_rejectedAsUnsupportedInput() {
        assertEquals("unsupportedInput", Arguments.validateMaxLongSidePx(15L))
    }

    @Test
    fun validateMaxLongSidePx_exactly16OrNullOrAbove_isValid() {
        assertEquals(null, Arguments.validateMaxLongSidePx(16L))
        assertEquals(null, Arguments.validateMaxLongSidePx(null))
        assertEquals(null, Arguments.validateMaxLongSidePx(1920L))
    }

    @Test
    fun validateVideoBitrateBps_nonPositive_rejectedAsUnsupportedInput() {
        assertEquals("unsupportedInput", Arguments.validateVideoBitrateBps(0L))
    }

    @Test
    fun validateVideoBitrateBps_positiveOrNull_isValid() {
        assertEquals(null, Arguments.validateVideoBitrateBps(1L))
        assertEquals(null, Arguments.validateVideoBitrateBps(null))
    }

    @Test
    fun validateTargetSizeMb_nonPositiveOrNonFinite_rejectedAsUnsupportedInput() {
        assertEquals("unsupportedInput", Arguments.validateTargetSizeMb(0.0))
        assertEquals("unsupportedInput", Arguments.validateTargetSizeMb(-1.0))
        assertEquals("unsupportedInput", Arguments.validateTargetSizeMb(Double.NaN))
        assertEquals(
            "unsupportedInput",
            Arguments.validateTargetSizeMb(Double.POSITIVE_INFINITY),
        )
    }

    @Test
    fun validateTargetSizeMb_smallPositiveOrNull_isValid() {
        assertEquals(null, Arguments.validateTargetSizeMb(0.001))
        assertEquals(null, Arguments.validateTargetSizeMb(null))
    }

    @Test
    fun validateSizeTargetsNotContradictory_bothSet_rejectedAsUnsupportedInput() {
        assertEquals(
            "unsupportedInput",
            Arguments.validateSizeTargetsNotContradictory(10.0, 2000000L),
        )
    }

    @Test
    fun validateSizeTargetsNotContradictory_atMostOneSet_isValid() {
        assertEquals(null, Arguments.validateSizeTargetsNotContradictory(10.0, null))
        assertEquals(null, Arguments.validateSizeTargetsNotContradictory(null, 2000000L))
        assertEquals(null, Arguments.validateSizeTargetsNotContradictory(null, null))
    }

    @Test
    fun validateTrimRange_negativeTrimStartMs_rejectedAsUnsupportedInput() {
        assertEquals("unsupportedInput", Arguments.validateTrimRange(-1L, null))
    }

    @Test
    fun validateTrimRange_trimEndMsNotStrictlyGreaterThanTrimStartMs_rejectedAsUnsupportedInput() {
        assertEquals("unsupportedInput", Arguments.validateTrimRange(1000L, 1000L))
        assertEquals("unsupportedInput", Arguments.validateTrimRange(1000L, 500L))
    }

    @Test
    fun validateTrimRange_validRange_isValid() {
        assertEquals(null, Arguments.validateTrimRange(1000L, 1001L))
        assertEquals(null, Arguments.validateTrimRange(null, null))
        assertEquals(null, Arguments.validateTrimRange(null, 500L))
    }

    @Test
    fun validateVideoCodec_notH264_rejectedAsUnsupportedInput() {
        assertEquals("unsupportedInput", Arguments.validateVideoCodec("hevc"))
    }

    @Test
    fun validateVideoCodec_h264_isValid() {
        assertEquals(null, Arguments.validateVideoCodec("h264"))
    }

    @Test
    fun validateHdrMode_notToneMapToSdr_rejectedAsUnsupportedInput() {
        assertEquals("unsupportedInput", Arguments.validateHdrMode("keepHdr"))
    }

    @Test
    fun validateHdrMode_toneMapToSdr_isValid() {
        assertEquals(null, Arguments.validateHdrMode("toneMapToSdr"))
    }

    @Test
    fun validateAudioReencode_zeroOrOutOfRangeChannels_rejectedAsUnsupportedInput() {
        assertEquals(
            "unsupportedInput",
            Arguments.validateAudioReencode(AudioModeMessage.REENCODE, 128000L, 0L),
        )
        assertEquals(
            "unsupportedInput",
            Arguments.validateAudioReencode(AudioModeMessage.REENCODE, 128000L, 3L),
        )
    }

    @Test
    fun validateAudioReencode_nonPositiveBitrate_rejectedAsUnsupportedInput() {
        assertEquals(
            "unsupportedInput",
            Arguments.validateAudioReencode(AudioModeMessage.REENCODE, 0L, 2L),
        )
        assertEquals(
            "unsupportedInput",
            Arguments.validateAudioReencode(AudioModeMessage.REENCODE, -1L, 2L),
        )
    }

    @Test
    fun validateAudioReencode_bitrateOf1_isValid_clampedNativelyBySizeGuardNotRejectedHere() {
        assertEquals(
            null,
            Arguments.validateAudioReencode(AudioModeMessage.REENCODE, 1L, 2L),
        )
    }

    @Test
    fun validateAudioReencode_oneOrTwoChannelsWithPositiveBitrate_isValid() {
        assertEquals(
            null,
            Arguments.validateAudioReencode(AudioModeMessage.REENCODE, 128000L, 1L),
        )
        assertEquals(
            null,
            Arguments.validateAudioReencode(AudioModeMessage.REENCODE, 128000L, 2L),
        )
    }

    @Test
    fun validateAudioReencode_notReencodeMode_ignoresBitrateAndChannels() {
        assertEquals(
            null,
            Arguments.validateAudioReencode(AudioModeMessage.PASSTHROUGH, null, null),
        )
        assertEquals(
            null,
            Arguments.validateAudioReencode(AudioModeMessage.STRIP, null, null),
        )
    }

    @Test
    fun requireValidCompressRequest_validRequest_doesNotThrow() {
        Arguments.requireValidCompressRequest(validCompressRequest())
    }

    @Test
    fun requireValidCompressRequest_maxFpsZero_throwsWithThatReason() {
        val error =
            assertFailsWith<CompressVideoError> {
                Arguments.requireValidCompressRequest(validCompressRequest().copy(maxFps = 0L))
            }
        assertEquals("unsupportedInput", error.code)
    }

    @Test
    fun requireValidCompressRequest_maxLongSidePxBelow16_throwsWithThatReason() {
        val error =
            assertFailsWith<CompressVideoError> {
                Arguments.requireValidCompressRequest(
                    validCompressRequest().copy(maxLongSidePx = 15L),
                )
            }
        assertEquals("unsupportedInput", error.code)
    }

    @Test
    fun requireValidCompressRequest_contradictoryTargets_throwsWithThatReason() {
        val error =
            assertFailsWith<CompressVideoError> {
                Arguments.requireValidCompressRequest(
                    validCompressRequest().copy(targetSizeMb = 10.0, videoBitrateBps = 2000000L),
                )
            }
        assertEquals("unsupportedInput", error.code)
    }

    @Test
    fun requireValidCompressRequest_invalidTrimRange_throwsWithThatReason() {
        val error =
            assertFailsWith<CompressVideoError> {
                Arguments.requireValidCompressRequest(
                    validCompressRequest().copy(trimStartMs = 1000L, trimEndMs = 1000L),
                )
            }
        assertEquals("unsupportedInput", error.code)
    }

    @Test
    fun requireValidCompressRequest_reencodeWithBadChannels_throwsWithThatReason() {
        val error =
            assertFailsWith<CompressVideoError> {
                Arguments.requireValidCompressRequest(
                    validCompressRequest().copy(
                        audioMode = AudioModeMessage.REENCODE,
                        audioBitrateBps = 128000L,
                        audioChannels = 3L,
                    ),
                )
            }
        assertEquals("unsupportedInput", error.code)
    }
}
