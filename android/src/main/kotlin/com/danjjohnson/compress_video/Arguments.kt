package com.danjjohnson.compress_video

import java.io.File

/**
 * Pure argument validation for a path about to be handed to a native file API.
 *
 * No file API beyond [File] itself is touched until this passes -- [Probe] calls this first,
 * on every request.
 */
object Arguments {
    /**
     * Resolves [path] to its canonical form and returns it as an existing, readable,
     * non-empty regular [File], or throws a [CompressVideoError] naming the specific
     * rejection reason.
     *
     * Canonicalising the path before use means a relative or traversing path cannot reach
     * outside what the caller's own process could already read -- the plugin runs inside the
     * host app's own sandbox, so this control cannot grant access the caller did not already
     * have. It exists to turn a traversal attempt into a typed [CompressVideoError] instead of
     * an unexpected native failure.
     */
    fun requireReadableMediaFile(path: String): File {
        if (path.isBlank()) {
            throw CompressVideoError(
                "unsupportedInput",
                "path must not be empty or whitespace-only",
            )
        }

        val canonical =
            try {
                File(path).canonicalFile
            } catch (e: Exception) {
                throw CompressVideoError("fileNotFound", "Could not resolve path", e.message)
            }

        if (!canonical.exists() || !canonical.isFile) {
            throw CompressVideoError("fileNotFound", "No readable file at the given path")
        }
        if (!canonical.canRead()) {
            throw CompressVideoError("fileNotFound", "File exists but is not readable")
        }
        if (canonical.length() == 0L) {
            throw CompressVideoError("unsupportedInput", "File is empty")
        }

        return canonical
    }

    /**
     * Resolves [outputPath] to its canonical form and requires its parent directory to already
     * exist and be writable, throwing a [CompressVideoError] with reason `"io"` if either
     * requirement fails -- before any bytes are written. This is the [T-01-11] traversal
     * mitigation: a canonicalised path cannot resolve outside what the caller's own process
     * could already write, and turning a bad destination into a typed error here means the
     * caller never sees a partial file or an unexpected native failure.
     */
    fun requireWritableOutputParent(outputPath: String): File {
        val canonical =
            try {
                File(outputPath).canonicalFile
            } catch (e: Exception) {
                throw CompressVideoError("io", "Could not resolve outputPath", e.message)
            }

        val parent = canonical.parentFile
        if (parent == null || !parent.exists() || !parent.isDirectory) {
            throw CompressVideoError("io", "outputPath's parent directory does not exist")
        }
        if (!parent.canWrite()) {
            throw CompressVideoError("io", "outputPath's parent directory is not writable")
        }

        return canonical
    }
}
