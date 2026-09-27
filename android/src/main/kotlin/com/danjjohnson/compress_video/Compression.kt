package com.danjjohnson.compress_video

import android.content.Context
import android.os.Looper
import android.os.StatFs
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

        // Pre-registered BEFORE any async/suspending work below, so a concurrent
        // awaitCompressResult(jobId) call -- issued by a caller on a background isolate right
        // after firing this call, per 05-02 -- can never lose a race against a fast job finishing
        // first (confirmed live: a cheap clip can finish in ~220ms). See
        // JobRegistry.resultDeferredFor.
        JobRegistry.resultDeferredFor(jobId)

        return try {
            val inputFile = Arguments.requireReadableMediaFile(path)
            val inputInfo = probe.getMediaInfo(path)

            val cacheDir = PluginFiles.cacheSubDir(context)
            val destinationFile =
                if (request.outputPath != null) {
                    Arguments.requireWritableOutputParent(request.outputPath)
                } else {
                    File(cacheDir, "$jobId.mp4")
                }

            // Pre-flight space check (D-18): after validation and probing, before a Transformer
            // exists -- a job that cannot possibly fit is never even attempted.
            requireSufficientFreeSpace(inputFile, inputInfo, request, destinationFile)

            val result =
                engine.compress(
                    jobId = jobId,
                    inputFile = inputFile,
                    inputInfo = inputInfo,
                    request = request,
                    destinationFile = destinationFile,
                ) { percent -> flutterApi.onProgress(jobId, percent) }
            // A no-op when engine.compress()'s own success branch already recorded this (the
            // normal case): completeResult only ever accepts the first value. Reached directly
            // (not a no-op) for the wouldUseOriginal/finishSuccess branches is impossible to
            // skip -- restated here only as the single point every return value flows through,
            // for callers reasoning about this function rather than TransformerEngine's
            // internals.
            JobRegistry.completeResult(jobId, Result.success(result))
            result
        } catch (e: Throwable) {
            // Every exception path here (validation, free-space, cancellation, encode failure)
            // reaches this catch WITHOUT ever awaiting an onProgress push, so -- unlike the
            // success paths above -- this outer catch-all alone is sufficient to make the
            // outcome available to awaitCompressResult; no separate per-branch hook is needed.
            JobRegistry.completeResult(jobId, Result.failure(e))
            throw e
        }
    }

    override suspend fun cancel(jobId: String) {
        requireMainLooper("cancel")
        requireValidJobId(jobId)
        JobRegistry.cancel(jobId)
    }

    /**
     * Resolves once the job identified by [jobId] reaches a terminal outcome, per
     * [CompressHostApi.awaitCompressResult]'s contract -- see that dartdoc for the full
     * rationale. Reads from the SAME [JobRegistry.resultDeferredFor] deferred [startCompress]
     * completes, so this never depends on [CompressVideoFlutterApi.onProgress] being
     * acknowledged.
     */
    override suspend fun awaitCompressResult(jobId: String): CompressResultMessage {
        requireMainLooper("awaitCompressResult")
        requireValidJobId(jobId)
        val outcome = JobRegistry.resultDeferredFor(jobId).await()
        JobRegistry.forgetResult(jobId)
        return outcome.getOrElse { throw it }
    }

    /**
     * Returns a pre-flight [EstimateMessage] for [request] against [path], without decoding a
     * single frame and without building a [TransformerEngine]/`Transformer` at all.
     *
     * Validates and probes exactly like [startCompress] does, then resolves [SizeGuard.Plan]
     * via [TransformerEngine.resolvePlan] -- the SAME shared resolver [startCompress] itself
     * calls (through `TransformerEngine.compress`'s own `resolvePlan` call) -- so this path and
     * the real job can never disagree about the predicted bytes, dimensions or which of
     * [SizeGuard.Plan.wouldTransmux]/[SizeGuard.Plan.wouldUseOriginal] would apply (D-19,
     * INFO-03). Deliberately does not assert the main Looper the way [startCompress]/[cancel]
     * do: nothing on this path builds a `Transformer` or touches [JobRegistry] (both of which
     * require it), and the whole point of `estimate()` is that a caller can ask before spending
     * battery on work that needs one.
     */
    override suspend fun estimate(
        path: String,
        request: CompressRequestMessage,
    ): EstimateMessage {
        Arguments.requireValidCompressRequest(request)
        val inputFile = Arguments.requireReadableMediaFile(path)
        val inputInfo = probe.getMediaInfo(path)

        val plan: SizeGuard.Plan = engine.resolvePlan(inputFile, inputInfo, request)

        return EstimateMessage(
            outputBytes = plan.predictedOutputBytes,
            durationMs = plan.outputDurationMs,
            widthPx = plan.targetWidthPx.toLong(),
            heightPx = plan.targetHeightPx.toLong(),
            wouldTransmux = plan.wouldTransmux,
            wouldUseOriginal = plan.wouldUseOriginal,
        )
    }

    /**
     * Deletes every file this plugin has written to its own cache directory, except a file a
     * still-running job is currently writing to (T-02-28) -- succeeds as a no-op when the
     * directory is empty or does not exist yet (D-15).
     *
     * Requires the main Looper: [JobRegistry.liveTempFilePaths] reads [JobRegistry]'s
     * main-thread-confined job map with no lock of its own.
     */
    override suspend fun clearCache() {
        requireMainLooper("clearCache")
        val cacheDir = PluginFiles.cacheSubDir(context)
        val skip = JobRegistry.liveTempFilePaths()
        PluginFiles.sweep(cacheDir, skip)
    }

    /**
     * Throws a [CompressVideoError] with reason `"outOfSpace"` when the destination
     * filesystem's free space is less than 1.2 times [engine]'s own predicted output size for
     * [request] against [inputInfo] -- computed via [TransformerEngine.resolvePlan], the SAME
     * resolution [engine.compress] itself will use, so this pre-flight check can never disagree
     * with what the real encode attempts. Reads [destinationFile]'s parent directory's free
     * space via [StatFs] -- that directory is guaranteed to already exist by this point, either
     * the plugin's own cache subdirectory ([PluginFiles.cacheSubDir]) or a caller-supplied
     * `outputPath` whose parent [Arguments.requireWritableOutputParent] already validated.
     *
     * The 1.2x safety margin (not a bare 1.0x) leaves headroom for the destination filesystem's
     * own block-size rounding and any other concurrent writer, so a job that lands right at the
     * predicted size does not fail here only to succeed by a hair on a less cautious device.
     */
    private suspend fun requireSufficientFreeSpace(
        inputFile: File,
        inputInfo: MediaInfoMessage,
        request: CompressRequestMessage,
        destinationFile: File,
    ) {
        val plan = engine.resolvePlan(inputFile, inputInfo, request)
        val destinationDir =
            destinationFile.parentFile
                ?: throw CompressVideoError("io", "Could not resolve the output directory")
        val freeBytes = StatFs(destinationDir.path).availableBytes
        val requiredBytes = (plan.predictedOutputBytes * FREE_SPACE_SAFETY_FACTOR).toLong()
        if (freeBytes < requiredBytes) {
            throw CompressVideoError(
                "outOfSpace",
                "Not enough free space to compress: predicted output is " +
                    "${plan.predictedOutputBytes} bytes, requiring approximately $requiredBytes " +
                    "bytes with a $FREE_SPACE_SAFETY_FACTOR safety margin, but only $freeBytes " +
                    "bytes are free on the destination filesystem",
            )
        }
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

        // D-18's pre-flight free-space margin: the destination filesystem must have at least
        // this many times the predicted output size free before an encode is even attempted.
        const val FREE_SPACE_SAFETY_FACTOR = 1.2
    }
}
