package com.danjjohnson.compress_video

import android.content.Context
import android.media.MediaExtractor
import android.media.MediaFormat
import android.media.MediaMetadataRetriever
import android.os.Build
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/**
 * [ProbeHostApi] implementation: reads media info off the platform thread via
 * [MediaMetadataRetriever] and [MediaExtractor].
 *
 * Holds no shared mutable request state, no in-flight flag and no singleton, so two calls in
 * flight at once never cross replies -- each call's local variables are its own.
 */
class Probe(
    private val context: Context,
) : ProbeHostApi {
    override suspend fun getMediaInfo(path: String): MediaInfoMessage =
        withContext(Dispatchers.IO) {
            val file = Arguments.requireReadableMediaFile(path)

            val retriever = MediaMetadataRetriever()
            val extractor = MediaExtractor()
            try {
                try {
                    retriever.setDataSource(file.path)
                    extractor.setDataSource(file.path)
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

                var hasAudio = false
                var videoFormat: MediaFormat? = null
                var videoTrackIndex = -1
                for (i in 0 until extractor.trackCount) {
                    val format = extractor.getTrackFormat(i)
                    val mime = format.getString(MediaFormat.KEY_MIME) ?: continue
                    if (mime.startsWith("audio/")) {
                        hasAudio = true
                    } else if (mime.startsWith("video/") && videoFormat == null) {
                        videoFormat = format
                        videoTrackIndex = i
                    }
                }

                val (widthPx, heightPx) =
                    MediaMath.displayedSize(codedWidthPx, codedHeightPx, rotationDegrees)
                val roundedDurationMs = MediaMath.roundHalfUpMs(durationRawMs)

                MediaInfoMessage(
                    durationMs = roundedDurationMs,
                    widthPx = widthPx.toLong(),
                    heightPx = heightPx.toLong(),
                    rotationDegrees = rotationDegrees.toLong(),
                    sizeBytes = file.length(),
                    videoCodec = MediaMath.normalizeCodec(videoFormat?.getString(MediaFormat.KEY_MIME)),
                    videoBitrateBps =
                        readVideoBitrateBps(videoFormat)
                            ?: estimateVideoBitrateBpsFromSamples(
                                extractor,
                                videoTrackIndex,
                                roundedDurationMs,
                            ),
                    frameRateFps = readFrameRateFps(videoFormat),
                    hasAudio = hasAudio,
                    isHdr = isHdr(retriever),
                )
            } catch (e: CompressVideoError) {
                throw e
            } catch (e: Exception) {
                throw CompressVideoError("io", "Failed to read media info", e.message)
            } finally {
                retriever.release()
                extractor.release()
            }
        }

    /**
     * Reads the video track's average bitrate, in bits per second, from the extractor track
     * format. Returns `null` -- never `0` -- when the key is absent, which is the container
     * bitrate's overall value, not the video track's own bitrate.
     */
    private fun readVideoBitrateBps(videoFormat: MediaFormat?): Long? {
        if (videoFormat == null || !videoFormat.containsKey(MediaFormat.KEY_BIT_RATE)) {
            return null
        }
        return try {
            videoFormat.getInteger(MediaFormat.KEY_BIT_RATE).toLong()
        } catch (e: Exception) {
            null
        }
    }

    /**
     * Falls back to estimating the video track's average bitrate by summing every sample's
     * byte size and dividing by [durationMs], for a container whose track format has no
     * [MediaFormat.KEY_BIT_RATE] entry at all.
     *
     * Found live on the emulator this plan (02-03): Media3's `InAppMp4Muxer` output never
     * carries a bitrate value [readVideoBitrateBps] can read back, which made
     * [MediaInfoMessage.videoBitrateBps] silently `null` for every one of the plugin's own
     * compressed outputs -- unlike the ffmpeg-authored corpus fixtures, which do carry one.
     * `null` there is meant to mean "the platform genuinely could not determine this", but for
     * a file this same process just finished writing, the platform demonstrably can determine
     * it, by direct measurement, so this fallback closes that gap rather than leaving a
     * silently unusable field on the plugin's own re-probe of its own output.
     *
     * Returns `null` -- never `0` -- when [videoTrackIndex] is invalid, [durationMs] is
     * non-positive, or no sample bytes could be read.
     */
    private fun estimateVideoBitrateBpsFromSamples(
        extractor: MediaExtractor,
        videoTrackIndex: Int,
        durationMs: Long,
    ): Long? {
        if (videoTrackIndex < 0 || durationMs <= 0) {
            return null
        }
        return try {
            extractor.selectTrack(videoTrackIndex)
            var totalBytes = 0L
            val buffer = java.nio.ByteBuffer.allocate(SAMPLE_READ_BUFFER_BYTES)
            while (true) {
                val sampleSize = extractor.readSampleData(buffer, 0)
                if (sampleSize < 0) break
                totalBytes += sampleSize
                if (!extractor.advance()) break
            }
            if (totalBytes <= 0L) {
                null
            } else {
                val durationSeconds = durationMs / 1000.0
                ((totalBytes * 8.0) / durationSeconds).toLong()
            }
        } catch (e: Exception) {
            null
        } finally {
            extractor.unselectTrack(videoTrackIndex)
        }
    }

    /**
     * Reads the video track's frame rate, in frames per second, from the extractor track
     * format. `KEY_FRAME_RATE` is reported as an `Int` by some extractors and a `Float` by
     * others depending on the source container, so both accessors are tried before giving up.
     */
    private fun readFrameRateFps(videoFormat: MediaFormat?): Double? {
        if (videoFormat == null || !videoFormat.containsKey(MediaFormat.KEY_FRAME_RATE)) {
            return null
        }
        return try {
            videoFormat.getInteger(MediaFormat.KEY_FRAME_RATE).toDouble()
        } catch (e: Exception) {
            try {
                videoFormat.getFloat(MediaFormat.KEY_FRAME_RATE).toDouble()
            } catch (e2: Exception) {
                null
            }
        }
    }

    /**
     * Detects HDR via the colour-transfer characteristic reported by
     * [MediaMetadataRetriever.METADATA_KEY_COLOR_TRANSFER].
     *
     * Confirmed 2026-09-15 against the "Added in API level" badge on
     * developer.android.com/reference/android/media/MediaMetadataRetriever:
     * `METADATA_KEY_COLOR_TRANSFER`/`_COLOR_STANDARD`/`_COLOR_RANGE` were all added in API
     * level 30 (Android 11) -- not the API 24/29 secondary-source guesses in
     * 01-RESEARCH.md's Open Questions. Reading it below API 30 either returns `null` (which
     * this code already treats as "not HDR") or is simply unavailable; the guard below still
     * exists so the intent is explicit rather than accidental. An unavailable key, or any
     * exception while reading it, maps to `false` -- never a crash.
     */
    private fun isHdr(retriever: MediaMetadataRetriever): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) {
            return false
        }
        return try {
            val colorTransfer =
                retriever
                    .extractMetadata(MediaMetadataRetriever.METADATA_KEY_COLOR_TRANSFER)
                    ?.toIntOrNull()
            colorTransfer == MediaFormat.COLOR_TRANSFER_HLG ||
                colorTransfer == MediaFormat.COLOR_TRANSFER_ST2084
        } catch (e: Exception) {
            false
        }
    }

    private companion object {
        // Generous for a single H.264 sample at any bitrate this project's presets or
        // targetSizeMb range produce; a too-small buffer would make readSampleData fail on a
        // large keyframe rather than under-count it.
        const val SAMPLE_READ_BUFFER_BYTES = 4 * 1024 * 1024
    }
}
