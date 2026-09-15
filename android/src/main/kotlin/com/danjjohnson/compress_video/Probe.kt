package com.danjjohnson.compress_video

import android.content.Context
import android.media.MediaMetadataRetriever
import java.io.File
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/**
 * [ProbeHostApi] implementation: reads media info off the platform thread via
 * [MediaMetadataRetriever].
 *
 * Holds no shared mutable request state, no in-flight flag and no singleton, so two calls in
 * flight at once never cross replies -- each call's local variables are its own.
 */
class Probe(
    private val context: Context,
) : ProbeHostApi {
    override suspend fun getMediaInfo(path: String): MediaInfoMessage =
        withContext(Dispatchers.IO) {
            val file = File(path)
            if (!file.exists() || !file.isFile || !file.canRead()) {
                throw CompressVideoError("fileNotFound", "No readable file at the given path")
            }

            val retriever = MediaMetadataRetriever()
            try {
                try {
                    retriever.setDataSource(path)
                } catch (e: Exception) {
                    throw CompressVideoError(
                        "unsupportedInput",
                        "The platform could not read this file as media",
                    )
                }

                val rotationDegrees =
                    retriever
                        .extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_ROTATION)
                        ?.toIntOrNull() ?: 0
                val codedWidthPx =
                    retriever
                        .extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_WIDTH)
                        ?.toIntOrNull() ?: 0
                val codedHeightPx =
                    retriever
                        .extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_HEIGHT)
                        ?.toIntOrNull() ?: 0
                val durationRawMs =
                    retriever
                        .extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)
                        ?.toDoubleOrNull() ?: 0.0
                val hasAudio =
                    retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_HAS_AUDIO) ==
                        "yes"

                val (widthPx, heightPx) =
                    MediaMath.displayedSize(codedWidthPx, codedHeightPx, rotationDegrees)

                MediaInfoMessage(
                    durationMs = MediaMath.roundHalfUpMs(durationRawMs),
                    widthPx = widthPx.toLong(),
                    heightPx = heightPx.toLong(),
                    rotationDegrees = rotationDegrees.toLong(),
                    sizeBytes = file.length(),
                    videoCodec = null,
                    videoBitrateBps = null,
                    frameRateFps = null,
                    hasAudio = hasAudio,
                    isHdr = false,
                )
            } catch (e: CompressVideoError) {
                throw e
            } catch (e: Exception) {
                throw CompressVideoError("io", "Failed to read media info", e.message)
            } finally {
                retriever.release()
            }
        }
}
