package com.danjjohnson.compress_video

import kotlin.test.Test
import kotlin.test.assertEquals

/**
 * Table-driven pure JVM tests for [ErrorMapping] -- no emulator, no `ExportException`
 * construction (which, like `Transformer`, cannot be constructed in a plain unit test; its
 * static initializer touches Android framework internals). One named case per one of the 22
 * documented `ExportException.errorCode` values, plus the unknown-code fallback and the
 * out-of-space message check in both directions.
 */
internal class ErrorMappingTest {
    @Test
    fun knownErrorCodes_hasExactlyTwentyTwoEntries() {
        // Fails the whole suite if a code is ever added to KNOWN_ERROR_CODES without a
        // corresponding case below -- 02-06-PLAN.md's own acceptance criterion.
        assertEquals(22, ErrorMapping.KNOWN_ERROR_CODES.size)
    }

    @Test
    fun errorCode_unspecified_mapsToUnknown() {
        assertEquals(
            "unknown",
            ErrorMapping.reasonForErrorCode(ErrorMapping.ERROR_CODE_UNSPECIFIED),
        )
    }

    @Test
    fun errorCode_failedRuntimeCheck_mapsToUnknown() {
        assertEquals(
            "unknown",
            ErrorMapping.reasonForErrorCode(ErrorMapping.ERROR_CODE_FAILED_RUNTIME_CHECK),
        )
    }

    @Test
    fun errorCode_ioUnspecified_mapsToIo() {
        assertEquals("io", ErrorMapping.reasonForErrorCode(ErrorMapping.ERROR_CODE_IO_UNSPECIFIED))
    }

    @Test
    fun errorCode_ioNetworkConnectionFailed_mapsToIo() {
        assertEquals(
            "io",
            ErrorMapping.reasonForErrorCode(
                ErrorMapping.ERROR_CODE_IO_NETWORK_CONNECTION_FAILED,
            ),
        )
    }

    @Test
    fun errorCode_ioNetworkConnectionTimeout_mapsToIo() {
        assertEquals(
            "io",
            ErrorMapping.reasonForErrorCode(
                ErrorMapping.ERROR_CODE_IO_NETWORK_CONNECTION_TIMEOUT,
            ),
        )
    }

    @Test
    fun errorCode_ioInvalidHttpContentType_mapsToIo() {
        assertEquals(
            "io",
            ErrorMapping.reasonForErrorCode(
                ErrorMapping.ERROR_CODE_IO_INVALID_HTTP_CONTENT_TYPE,
            ),
        )
    }

    @Test
    fun errorCode_ioBadHttpStatus_mapsToIo() {
        assertEquals(
            "io",
            ErrorMapping.reasonForErrorCode(ErrorMapping.ERROR_CODE_IO_BAD_HTTP_STATUS),
        )
    }

    @Test
    fun errorCode_ioFileNotFound_mapsToFileNotFound() {
        assertEquals(
            "fileNotFound",
            ErrorMapping.reasonForErrorCode(ErrorMapping.ERROR_CODE_IO_FILE_NOT_FOUND),
        )
    }

    @Test
    fun errorCode_ioNoPermission_mapsToIo() {
        assertEquals(
            "io",
            ErrorMapping.reasonForErrorCode(ErrorMapping.ERROR_CODE_IO_NO_PERMISSION),
        )
    }

    @Test
    fun errorCode_ioCleartextNotPermitted_mapsToIo() {
        assertEquals(
            "io",
            ErrorMapping.reasonForErrorCode(ErrorMapping.ERROR_CODE_IO_CLEARTEXT_NOT_PERMITTED),
        )
    }

    @Test
    fun errorCode_ioReadPositionOutOfRange_mapsToIo() {
        assertEquals(
            "io",
            ErrorMapping.reasonForErrorCode(
                ErrorMapping.ERROR_CODE_IO_READ_POSITION_OUT_OF_RANGE,
            ),
        )
    }

    @Test
    fun errorCode_decoderInitFailed_mapsToDecoderUnavailable() {
        assertEquals(
            "decoderUnavailable",
            ErrorMapping.reasonForErrorCode(ErrorMapping.ERROR_CODE_DECODER_INIT_FAILED),
        )
    }

    @Test
    fun errorCode_decodingFailed_mapsToUnsupportedInput() {
        assertEquals(
            "unsupportedInput",
            ErrorMapping.reasonForErrorCode(ErrorMapping.ERROR_CODE_DECODING_FAILED),
        )
    }

    @Test
    fun errorCode_decodingFormatUnsupported_mapsToUnsupportedInput() {
        assertEquals(
            "unsupportedInput",
            ErrorMapping.reasonForErrorCode(ErrorMapping.ERROR_CODE_DECODING_FORMAT_UNSUPPORTED),
        )
    }

    @Test
    fun errorCode_encoderInitFailed_mapsToEncoderUnavailable() {
        assertEquals(
            "encoderUnavailable",
            ErrorMapping.reasonForErrorCode(ErrorMapping.ERROR_CODE_ENCODER_INIT_FAILED),
        )
    }

    @Test
    fun errorCode_encodingFailed_mapsToEncoderUnavailable() {
        assertEquals(
            "encoderUnavailable",
            ErrorMapping.reasonForErrorCode(ErrorMapping.ERROR_CODE_ENCODING_FAILED),
        )
    }

    @Test
    fun errorCode_encodingFormatUnsupported_mapsToEncoderUnavailable() {
        assertEquals(
            "encoderUnavailable",
            ErrorMapping.reasonForErrorCode(ErrorMapping.ERROR_CODE_ENCODING_FORMAT_UNSUPPORTED),
        )
    }

    @Test
    fun errorCode_videoFrameProcessingFailed_mapsToIo() {
        assertEquals(
            "io",
            ErrorMapping.reasonForErrorCode(
                ErrorMapping.ERROR_CODE_VIDEO_FRAME_PROCESSING_FAILED,
            ),
        )
    }

    @Test
    fun errorCode_audioProcessingFailed_mapsToIo() {
        assertEquals(
            "io",
            ErrorMapping.reasonForErrorCode(ErrorMapping.ERROR_CODE_AUDIO_PROCESSING_FAILED),
        )
    }

    @Test
    fun errorCode_muxingFailed_mapsToIo() {
        assertEquals(
            "io",
            ErrorMapping.reasonForErrorCode(ErrorMapping.ERROR_CODE_MUXING_FAILED),
        )
    }

    @Test
    fun errorCode_muxingTimeout_mapsToIo() {
        assertEquals(
            "io",
            ErrorMapping.reasonForErrorCode(ErrorMapping.ERROR_CODE_MUXING_TIMEOUT),
        )
    }

    @Test
    fun errorCode_muxingAppend_mapsToIo() {
        // 02-RESEARCH.md Pitfall 9: the third muxing code CONTEXT.md's own table did not name.
        assertEquals(
            "io",
            ErrorMapping.reasonForErrorCode(ErrorMapping.ERROR_CODE_MUXING_APPEND),
        )
    }

    @Test
    fun errorCode_outsideTheKnownSet_mapsToUnknown() {
        assertEquals("unknown", ErrorMapping.reasonForErrorCode(999_999))
    }

    @Test
    fun reasonForExportFailure_nullCauseMessage_defersToTheCodeMapping() {
        assertEquals(
            "fileNotFound",
            ErrorMapping.reasonForExportFailure(ErrorMapping.ERROR_CODE_IO_FILE_NOT_FOUND, null),
        )
    }

    @Test
    fun reasonForExportFailure_unrelatedCauseMessage_defersToTheCodeMapping() {
        assertEquals(
            "unsupportedInput",
            ErrorMapping.reasonForExportFailure(
                ErrorMapping.ERROR_CODE_DECODING_FAILED,
                "some unrelated decode failure message",
            ),
        )
    }

    @Test
    fun reasonForExportFailure_causeMessageMentionsEnospc_mapsToOutOfSpace() {
        assertEquals(
            "outOfSpace",
            ErrorMapping.reasonForExportFailure(
                ErrorMapping.ERROR_CODE_IO_UNSPECIFIED,
                "write failed: ENOSPC (No space left on device)",
            ),
        )
    }

    @Test
    fun reasonForExportFailure_causeMessageMentionsNoSpaceLeftOnDevice_mapsToOutOfSpace() {
        assertEquals(
            "outOfSpace",
            ErrorMapping.reasonForExportFailure(
                ErrorMapping.ERROR_CODE_MUXING_FAILED,
                "java.io.IOException: No space left on device",
            ),
        )
    }

    @Test
    fun reasonForExportFailure_causeMessageCaseInsensitive_mapsToOutOfSpace() {
        assertEquals(
            "outOfSpace",
            ErrorMapping.reasonForExportFailure(
                ErrorMapping.ERROR_CODE_IO_UNSPECIFIED,
                "Write failed: enospc",
            ),
        )
    }
}
