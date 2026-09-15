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
}
