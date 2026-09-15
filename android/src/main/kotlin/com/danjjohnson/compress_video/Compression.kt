package com.danjjohnson.compress_video

import android.content.Context
import android.os.Looper
import java.io.File

/**
 * [CompressHostApi] implementation.
 *
 * Every entry point asserts it is running on the main Looper before doing anything else --
 * Media3's `Transformer` requires it (02-RESEARCH.md Pattern 1, Open Question 1) -- then probes
 * the input off the platform thread via [probe] (whose own `withContext(Dispatchers.IO)` always
 * resumes back on this call's original, main-Looper context) before handing everything else to
 * [engine] on the main Looper.
 */
class Compression(
    private val context: Context,
    private val probe: Probe,
    private val flutterApi: CompressVideoFlutterApi,
    private val engine: TransformerEngine = TransformerEngine(context),
) : CompressHostApi {
    override suspend fun startCompress(
        path: String,
        jobId: String,
        request: CompressRequestMessage,
    ): CompressResultMessage {
        requireMainLooper("startCompress")
        requireValidJobId(jobId)
        Arguments.requireValidCompressRequest(request)

        val inputFile = Arguments.requireReadableMediaFile(path)
        val inputInfo = probe.getMediaInfo(path)

        val cacheDir = PluginFiles.cacheSubDir(context)
        val destinationFile =
            if (request.outputPath != null) {
                Arguments.requireWritableOutputParent(request.outputPath)
            } else {
                File(cacheDir, "$jobId.mp4")
            }

        return engine.compress(
            jobId = jobId,
            inputFile = inputFile,
            inputInfo = inputInfo,
            request = request,
            destinationFile = destinationFile,
        ) { percent -> flutterApi.onProgress(jobId, percent) }
    }

    override suspend fun cancel(jobId: String) {
        requireMainLooper("cancel")
        requireValidJobId(jobId)
        JobRegistry.cancel(jobId)
    }

    /** Not yet implemented on Android -- lands in plan 02-07 (`SizeGuard`). */
    override suspend fun estimate(
        path: String,
        request: CompressRequestMessage,
    ): EstimateMessage {
        throw CompressVideoError("unsupportedInput", "estimate() is implemented in plan 02-07")
    }

    /** Not yet implemented on Android -- lands in plan 02-07. */
    override suspend fun clearCache() {
        throw CompressVideoError("unsupportedInput", "clearCache() is implemented in plan 02-07")
    }

    /**
     * Throws a typed error naming [caller] if the current thread is not the main Looper --
     * the one-line check 02-RESEARCH.md's Open Question 1 asks for: Media3's `Transformer`
     * throws an unchecked `IllegalStateException` from every one of its own calls off its
     * building thread, which would otherwise surface as an unexplained native crash instead of
     * a typed, diagnosable error.
     */
    private fun requireMainLooper(caller: String) {
        if (Looper.myLooper() != Looper.getMainLooper()) {
            throw CompressVideoError(
                "unknown",
                "CompressHostApi.$caller must run on the main Looper",
            )
        }
    }

    /**
     * Validates [jobId] against the documented `<monotonic counter>-<16 lowercase hex
     * characters>` format before it is ever used as a filename stem (T-02-04).
     */
    private fun requireValidJobId(jobId: String) {
        if (!JOB_ID_PATTERN.matches(jobId)) {
            throw CompressVideoError(
                "unsupportedInput",
                "jobId does not match the required <counter>-<16 lowercase hex characters> pattern",
            )
        }
    }

    private companion object {
        val JOB_ID_PATTERN = Regex("^[0-9]+-[0-9a-f]{16}$")
    }
}
