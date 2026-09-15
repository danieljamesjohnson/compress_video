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
}
