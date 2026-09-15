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
}
