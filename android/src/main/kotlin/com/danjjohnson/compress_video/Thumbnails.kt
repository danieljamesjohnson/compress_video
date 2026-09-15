package com.danjjohnson.compress_video

import android.content.Context
import android.graphics.Bitmap
import android.media.MediaMetadataRetriever
import android.os.Build
import java.io.ByteArrayOutputStream
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/**
 * [ThumbnailHostApi] implementation: extracts a rotation-correct poster frame off the platform
 * thread via [MediaMetadataRetriever], exactly as [Probe] does for media info.
 *
 * [getThumbnail] and [getThumbnailFile] share one frame-extraction-and-encode path
 * ([extractThumbnailJpeg]) so the two entry points can never drift apart in how they convert
 * [positionMs], scale, or encode -- only where the resulting bytes end up differs.
 */
class Thumbnails(
    private val context: Context,
) : ThumbnailHostApi {
    override suspend fun getThumbnail(
        path: String,
        positionMs: Long,
        quality: Long,
        maxDimensionPx: Long?,
    ): ByteArray =
        withContext(Dispatchers.IO) {
            extractThumbnailJpeg(path, positionMs, quality, maxDimensionPx)
        }

    override suspend fun getThumbnailFile(
        path: String,
        positionMs: Long,
        quality: Long,
        maxDimensionPx: Long?,
        outputPath: String?,
    ): String =
        withContext(Dispatchers.IO) {
            // Minimal placeholder to satisfy the ThumbnailHostApi interface for this task;
            // uniqueness, atomic placement and outputPath support are added in the next task.
            val jpegBytes = extractThumbnailJpeg(path, positionMs, quality, maxDimensionPx)
            val cacheSubDir = java.io.File(context.cacheDir, "compress_video")
            if (!cacheSubDir.exists()) {
                cacheSubDir.mkdirs()
            }
            val file = java.io.File(cacheSubDir, uniqueThumbnailFileName())
            file.writeBytes(jpegBytes)
            file.canonicalPath
        }

    /**
     * Reads the requested frame from [path] at [positionMs] and returns it JPEG-encoded at
     * [quality], with the longer displayed side capped at [maxDimensionPx] (never upscaled).
     *
     * [positionMs] is converted to microseconds at this single point -- the only place in this
     * class a unit conversion happens -- and the frame is requested with
     * [MediaMetadataRetriever.OPTION_CLOSEST] (the exact requested frame) rather than
     * [MediaMetadataRetriever.OPTION_CLOSEST_SYNC] (the nearest keyframe), so the returned
     * frame is the one at the requested moment, not a preceding sync frame. The retriever
     * already applies the track's display rotation to the returned bitmap -- no rotation math
     * is done here.
     */
    private fun extractThumbnailJpeg(
        path: String,
        positionMs: Long,
        quality: Long,
        maxDimensionPx: Long?,
    ): ByteArray {
        val file = Arguments.requireReadableMediaFile(path)
        val positionUs = positionMs * 1000

        val retriever = MediaMetadataRetriever()
        var bitmap: Bitmap? = null
        try {
            try {
                retriever.setDataSource(file.path)
            } catch (e: Exception) {
                throw CompressVideoError(
                    "unsupportedInput",
                    "The platform could not read this file as media",
                )
            }

            val codedWidthPx =
                retriever
                    .extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_WIDTH)
                    ?.toIntOrNull() ?: 0
            val codedHeightPx =
                retriever
                    .extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_HEIGHT)
                    ?.toIntOrNull() ?: 0
            val rotationDegrees =
                retriever
                    .extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_ROTATION)
                    ?.toIntOrNull() ?: 0
            val (displayedWidthPx, displayedHeightPx) =
                MediaMath.displayedSize(codedWidthPx, codedHeightPx, rotationDegrees)
            val (targetWidthPx, targetHeightPx) =
                MediaMath.scaledSize(displayedWidthPx, displayedHeightPx, maxDimensionPx?.toInt())

            bitmap =
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
                    // getScaledFrameAtTime (API 27+) decodes directly at the target size and
                    // still applies the display rotation to the returned bitmap.
                    retriever.getScaledFrameAtTime(
                        positionUs,
                        MediaMetadataRetriever.OPTION_CLOSEST,
                        targetWidthPx,
                        targetHeightPx,
                    )
                } else {
                    val fullSizeFrame =
                        retriever.getFrameAtTime(positionUs, MediaMetadataRetriever.OPTION_CLOSEST)
                    if (fullSizeFrame != null &&
                        (fullSizeFrame.width != targetWidthPx || fullSizeFrame.height != targetHeightPx)
                    ) {
                        val scaled =
                            Bitmap.createScaledBitmap(
                                fullSizeFrame,
                                targetWidthPx,
                                targetHeightPx,
                                true,
                            )
                        if (scaled !== fullSizeFrame) {
                            fullSizeFrame.recycle()
                        }
                        scaled
                    } else {
                        fullSizeFrame
                    }
                }

            val decodedFrame =
                bitmap
                    ?: throw CompressVideoError(
                        "unsupportedInput",
                        "No frame could be decoded at the requested position",
                    )

            val stream = ByteArrayOutputStream()
            decodedFrame.compress(Bitmap.CompressFormat.JPEG, quality.toInt(), stream)
            return stream.toByteArray()
        } catch (e: CompressVideoError) {
            throw e
        } catch (e: Exception) {
            throw CompressVideoError("io", "Failed to extract thumbnail frame", e.message)
        } finally {
            bitmap?.recycle()
            retriever.release()
        }
    }

    companion object {
        private val random = java.security.SecureRandom()

        private fun uniqueThumbnailFileName(): String =
            "compress_video_thumb_${System.currentTimeMillis()}_${randomHex(8)}.jpg"

        private fun randomHex(length: Int): String {
            val bytes = ByteArray((length + 1) / 2)
            random.nextBytes(bytes)
            return bytes.joinToString("") { "%02x".format(it) }.take(length)
        }
    }
}
