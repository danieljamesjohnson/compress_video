package com.danjjohnson.compress_video

import android.content.Context
import java.io.File
import java.security.SecureRandom

/**
 * The single definition of where this plugin writes files, and the atomic-write/delete helpers
 * every file-producing native call in this plugin shares.
 *
 * Every file this plugin creates lives inside the `compress_video` subdirectory of the app's
 * own cache directory (D-15) -- never external or shared storage, and no storage permission is
 * ever requested. The shapes here are lifted directly from [Thumbnails]'s own atomic-write
 * pattern rather than reinvented.
 */
object PluginFiles {
    private val random = SecureRandom()

    /**
     * Returns the plugin's own cache subdirectory, creating it if it does not already exist.
     * Throws a [CompressVideoError] with reason `"io"` if it cannot be created.
     */
    fun cacheSubDir(context: Context): File {
        val dir = File(context.cacheDir, "compress_video")
        if (!dir.exists() && !dir.mkdirs() && !dir.exists()) {
            throw CompressVideoError("io", "Could not create the plugin cache directory")
        }
        return dir
    }

    /**
     * Returns a temp file beside [destination] -- the same directory, so the later
     * [moveIntoPlace] rename is atomic on every filesystem.
     */
    fun tempFileBeside(destination: File): File =
        File(destination.parentFile, "${destination.name}.tmp-${randomHex(8)}")

    /**
     * Renames [tempFile] into [destination], throwing a [CompressVideoError] with reason
     * `"io"` on failure. Touches no file other than these two.
     */
    fun moveIntoPlace(
        tempFile: File,
        destination: File,
    ) {
        if (!tempFile.renameTo(destination)) {
            throw CompressVideoError("io", "Could not move the output into place")
        }
    }

    /** Deletes [file] if it exists, ignoring the result -- used on every failure/cancel path. */
    fun quietDelete(file: File?) {
        file?.delete()
    }

    /**
     * Deletes the immediate contents of [cacheDir], except [skipCanonicalPaths] (files a
     * still-running job owns) and anything whose canonical path resolves outside [cacheDir]'s
     * own canonical path -- a symbolic link placed inside the directory cannot be used to walk
     * a delete outside it (T-02-26). A no-op, not an error, when [cacheDir] does not exist.
     *
     * A single, bounded [File.listFiles] call over [cacheDir] itself -- never a recursive tree
     * walk, and never a touch of [cacheDir]'s own parent. A subdirectory placed inside
     * [cacheDir] is deleted only if [File.delete] can remove it as-is (an empty directory); a
     * non-empty one is left alone rather than walked into, which this plugin never creates in
     * the first place.
     */
    fun sweep(
        cacheDir: File,
        skipCanonicalPaths: Set<String>,
    ) {
        val canonicalCacheDir =
            try {
                cacheDir.canonicalFile
            } catch (e: Exception) {
                return
            }
        val entries = cacheDir.listFiles() ?: return
        val cacheDirPrefix = canonicalCacheDir.path + File.separator

        for (entry in entries) {
            val canonicalEntry =
                try {
                    entry.canonicalFile
                } catch (e: Exception) {
                    continue
                }
            if (!canonicalEntry.path.startsWith(cacheDirPrefix)) {
                // Escapes the plugin's own directory (a symbolic link pointing elsewhere) --
                // never delete something this sweep did not create.
                continue
            }
            if (canonicalEntry.path in skipCanonicalPaths) {
                continue
            }
            entry.delete()
        }
    }

    private fun randomHex(length: Int): String {
        val bytes = ByteArray((length + 1) / 2)
        random.nextBytes(bytes)
        return bytes.joinToString("") { "%02x".format(it) }.take(length)
    }
}
