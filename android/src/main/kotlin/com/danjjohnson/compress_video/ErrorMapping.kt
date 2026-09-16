package com.danjjohnson.compress_video

/**
 * Pure mapping from an `androidx.media3.transformer.ExportException.errorCode` integer to a
 * [CompressVideoErrorReason] name string.
 *
 * No Android framework import and no Media3 import -- exercisable as plain JVM code with no
 * emulator, exactly like [MediaMath] and [SizeGuard]. [ErrorMappingTest] proves every one of
 * the 22 documented codes, plus the out-of-space message check, without ever constructing an
 * `ExportException` (which, like `Transformer`, cannot be constructed in a plain unit test).
 *
 * The 22 codes below are quoted verbatim from `ExportException.java`, androidx/media `release`
 * branch, read this plan (02-06) -- see 02-RESEARCH.md's "Full ExportException.errorCode ->
 * CompressVideoErrorReason mapping" for the source citation and the reasoning behind each
 * bucket, including the two ambiguous groups (Pitfall 8) and the third muxing code
 * (`MUXING_APPEND`, Pitfall 9) that 02-CONTEXT.md's own table did not name.
 */
object ErrorMapping {
    const val ERROR_CODE_UNSPECIFIED = 1000
    const val ERROR_CODE_FAILED_RUNTIME_CHECK = 1001
    const val ERROR_CODE_IO_UNSPECIFIED = 2000
    const val ERROR_CODE_IO_NETWORK_CONNECTION_FAILED = 2001
    const val ERROR_CODE_IO_NETWORK_CONNECTION_TIMEOUT = 2002
    const val ERROR_CODE_IO_INVALID_HTTP_CONTENT_TYPE = 2003
    const val ERROR_CODE_IO_BAD_HTTP_STATUS = 2004
    const val ERROR_CODE_IO_FILE_NOT_FOUND = 2005
    const val ERROR_CODE_IO_NO_PERMISSION = 2006
    const val ERROR_CODE_IO_CLEARTEXT_NOT_PERMITTED = 2007
    const val ERROR_CODE_IO_READ_POSITION_OUT_OF_RANGE = 2008
    const val ERROR_CODE_DECODER_INIT_FAILED = 3001
    const val ERROR_CODE_DECODING_FAILED = 3002
    const val ERROR_CODE_DECODING_FORMAT_UNSUPPORTED = 3003
    const val ERROR_CODE_ENCODER_INIT_FAILED = 4001
    const val ERROR_CODE_ENCODING_FAILED = 4002
    const val ERROR_CODE_ENCODING_FORMAT_UNSUPPORTED = 4003
    const val ERROR_CODE_VIDEO_FRAME_PROCESSING_FAILED = 5001
    const val ERROR_CODE_AUDIO_PROCESSING_FAILED = 6001
    const val ERROR_CODE_MUXING_FAILED = 7001
    const val ERROR_CODE_MUXING_TIMEOUT = 7002
    const val ERROR_CODE_MUXING_APPEND = 7003

    /**
     * Every code [ExportException] can report, exactly 22 -- [ErrorMappingTest] asserts this
     * set's size directly, so a future code added to the table without a corresponding test
     * case fails the suite rather than silently falling through [reasonForErrorCode]'s `else`
     * branch unnoticed.
     */
    val KNOWN_ERROR_CODES: Set<Int> =
        setOf(
            ERROR_CODE_UNSPECIFIED,
            ERROR_CODE_FAILED_RUNTIME_CHECK,
            ERROR_CODE_IO_UNSPECIFIED,
            ERROR_CODE_IO_NETWORK_CONNECTION_FAILED,
            ERROR_CODE_IO_NETWORK_CONNECTION_TIMEOUT,
            ERROR_CODE_IO_INVALID_HTTP_CONTENT_TYPE,
            ERROR_CODE_IO_BAD_HTTP_STATUS,
            ERROR_CODE_IO_FILE_NOT_FOUND,
            ERROR_CODE_IO_NO_PERMISSION,
            ERROR_CODE_IO_CLEARTEXT_NOT_PERMITTED,
            ERROR_CODE_IO_READ_POSITION_OUT_OF_RANGE,
            ERROR_CODE_DECODER_INIT_FAILED,
            ERROR_CODE_DECODING_FAILED,
            ERROR_CODE_DECODING_FORMAT_UNSUPPORTED,
            ERROR_CODE_ENCODER_INIT_FAILED,
            ERROR_CODE_ENCODING_FAILED,
            ERROR_CODE_ENCODING_FORMAT_UNSUPPORTED,
            ERROR_CODE_VIDEO_FRAME_PROCESSING_FAILED,
            ERROR_CODE_AUDIO_PROCESSING_FAILED,
            ERROR_CODE_MUXING_FAILED,
            ERROR_CODE_MUXING_TIMEOUT,
            ERROR_CODE_MUXING_APPEND,
        )

    /**
     * Maps [errorCode] to a [CompressVideoErrorReason] name string (for example
     * `"fileNotFound"`). A code outside [KNOWN_ERROR_CODES] returns `"unknown"` -- the caller is
     * responsible for preserving [errorCode] itself as the error's detail, exactly as
     * [CompressVideoException]'s own `reasonFromPlatformCode` round trip already does for a
     * reason name this Dart version does not recognise (never bucketing an unrecognised code
     * into a generic reason WITHOUT preserving the original, per this plan's own prohibition).
     */
    fun reasonForErrorCode(errorCode: Int): String =
        when (errorCode) {
            ERROR_CODE_IO_FILE_NOT_FOUND -> "fileNotFound"
            ERROR_CODE_IO_UNSPECIFIED,
            ERROR_CODE_IO_NETWORK_CONNECTION_FAILED,
            ERROR_CODE_IO_NETWORK_CONNECTION_TIMEOUT,
            ERROR_CODE_IO_INVALID_HTTP_CONTENT_TYPE,
            ERROR_CODE_IO_BAD_HTTP_STATUS,
            ERROR_CODE_IO_NO_PERMISSION,
            ERROR_CODE_IO_CLEARTEXT_NOT_PERMITTED,
            ERROR_CODE_IO_READ_POSITION_OUT_OF_RANGE,
            -> "io"
            ERROR_CODE_DECODER_INIT_FAILED -> "decoderUnavailable"
            ERROR_CODE_DECODING_FAILED,
            ERROR_CODE_DECODING_FORMAT_UNSUPPORTED,
            -> "unsupportedInput"
            ERROR_CODE_ENCODER_INIT_FAILED,
            ERROR_CODE_ENCODING_FORMAT_UNSUPPORTED,
            ERROR_CODE_ENCODING_FAILED,
            -> "encoderUnavailable"
            ERROR_CODE_VIDEO_FRAME_PROCESSING_FAILED,
            ERROR_CODE_AUDIO_PROCESSING_FAILED,
            ERROR_CODE_MUXING_FAILED,
            ERROR_CODE_MUXING_TIMEOUT,
            ERROR_CODE_MUXING_APPEND,
            -> "io"
            else -> "unknown"
        }

    /**
     * Maps an export failure to a [CompressVideoErrorReason] name string: returns
     * `"outOfSpace"` when [causeMessage] indicates the destination filesystem is full,
     * otherwise defers to [reasonForErrorCode].
     *
     * Media3 has no dedicated `ERROR_CODE_OUT_OF_SPACE` (02-RESEARCH.md Assumption A2), so this
     * message-string check is a best-effort SECONDARY defence -- the pre-flight free-space check
     * in `Compression.kt` (against 1.2x the predicted output) is the primary one and does not
     * depend on this string matching across Android versions or devices.
     */
    fun reasonForExportFailure(
        errorCode: Int,
        causeMessage: String?,
    ): String {
        if (causeMessage != null && isOutOfSpaceMessage(causeMessage)) {
            return "outOfSpace"
        }
        return reasonForErrorCode(errorCode)
    }

    private fun isOutOfSpaceMessage(message: String): Boolean {
        val lower = message.lowercase()
        return lower.contains("enospc") || lower.contains("no space left on device")
    }
}
