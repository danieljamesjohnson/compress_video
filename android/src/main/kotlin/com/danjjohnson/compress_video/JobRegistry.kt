package com.danjjohnson.compress_video

import android.os.Handler
import java.io.File
import kotlinx.coroutines.CompletableDeferred

/**
 * Main-thread-confined registry of live compression jobs, keyed by job id.
 *
 * Every method here must be called from the main thread -- the same thread every
 * `androidx.media3.transformer.Transformer` in this plugin is built and driven on
 * ([TransformerEngine], 02-RESEARCH.md Pattern 1). Main-thread confinement is the
 * synchronization here: there is no lock and no cross-thread mutable state.
 *
 * No Media3 or other Android-framework import beyond [Handler] -- [LiveJob] holds a
 * [LiveJob.cancelTransformer] callback rather than a `Transformer` reference directly, which
 * keeps this whole object exercisable with plain JVM test doubles (`CompressVideoPluginTest`'s
 * detach cases construct a [LiveJob] with no real `Transformer`, no Looper and no emulator --
 * `Transformer`'s own static initializer touches Android framework internals that are not
 * available outside a real device/emulator or Robolectric, so a real or mocked `Transformer`
 * instance cannot exist in that test at all).
 */
object JobRegistry {
    /**
     * One job's live state: how to cancel the operation driving it, the temp file it is writing
     * to, how to stop its progress polling, and how to resolve it when cancelled from outside
     * its own completion callback.
     */
    class LiveJob(
        val cancelTransformer: () -> Unit,
        val tempFile: File,
        val mainHandler: Handler,
        val progressRunnable: Runnable,
        val onCancelled: (reason: String) -> Unit,
    ) {
        internal var cancelled: Boolean = false

        /**
         * Set by [stopPolling] the instant a job's `Transformer.Listener` terminal callback
         * (`onCompleted`/`onError`) fires -- BEFORE the suspended `compress()` coroutine's own
         * continuation has resumed and called [remove] (WR-01). A job that is [terminal] has
         * already resolved its outcome (success or failure) on the native side; [cancel] must
         * treat it exactly like an already-cancelled job and no-op, rather than deleting a temp
         * file the still-suspended `compress()` call may be about to move into place.
         */
        internal var terminal: Boolean = false
    }

    private val jobs = LinkedHashMap<String, LiveJob>()

    /** Registers [job] under [jobId]. Must be called on the main thread. */
    fun register(
        jobId: String,
        job: LiveJob,
    ) {
        jobs[jobId] = job
    }

    /** Returns the live job for [jobId], or `null` if it is unknown or already finished. */
    fun find(jobId: String): LiveJob? = jobs[jobId]

    /**
     * Stops [jobId]'s progress polling and forgets it, without touching its files or invoking
     * its cancellation callback -- the normal path once a job's own completion callback has
     * already resolved it.
     */
    fun remove(jobId: String) {
        val job = jobs.remove(jobId) ?: return
        job.mainHandler.removeCallbacks(job.progressRunnable)
    }

    /**
     * Stops [jobId]'s progress polling WITHOUT forgetting it or touching its files, and marks it
     * [LiveJob.terminal] -- called from [TransformerEngine]'s `Transformer.Listener` terminal
     * callbacks (`onCompleted`/`onError`) the instant they fire, rather than relying on [remove]
     * after the suspended `compress` call resumes. The `Transformer` class javadoc states that
     * `getProgress` reports `PROGRESS_STATE_NOT_STARTED` once an export completes, so the
     * polling loop must stop itself proactively; stopping it here, synchronously inside the same
     * main-Looper callback that already fired, closes the (normally harmless, but unnecessary)
     * window between the listener firing and the coroutine's own cleanup running.
     *
     * Marking [LiveJob.terminal] here (WR-01) closes a SECOND, harmful window: the job stays
     * registered in [jobs] (with [LiveJob.cancelled] still `false`) until the suspended
     * `compress()` coroutine's own continuation resumes and calls [remove] -- a separately
     * scheduled main-Looper task. A [cancel] call arriving in that window used to see a
     * still-registered, not-yet-cancelled job and delete its temp file out from under the
     * about-to-succeed `compress()` call. [cancel] now checks [LiveJob.terminal] and no-ops
     * once it is set, so whichever of cancel/completion reaches the job second is the no-op.
     * A no-op if [jobId] is unknown.
     */
    fun stopPolling(jobId: String) {
        val job = jobs[jobId] ?: return
        job.mainHandler.removeCallbacks(job.progressRunnable)
        job.terminal = true
    }

    /**
     * Cancels the job identified by [jobId]: stops its progress polling, cancels the underlying
     * export via [LiveJob.cancelTransformer], deletes its temp output file, forgets it, and
     * invokes its [LiveJob.onCancelled] callback (with [reason]) so the suspended
     * `startCompress` call can fail with a typed error naming it. A no-op if [jobId] is
     * unknown, already cancelled, or already [LiveJob.terminal] -- so cancelling twice,
     * cancelling after the job already finished (successfully or not) and was removed from this
     * registry, or cancelling in the window between the job's own `Transformer.Listener`
     * terminal callback firing (WR-01: see [stopPolling]) and its `compress()` coroutine
     * actually removing it, deletes nothing and resolves without error -- the job's own outcome
     * is authoritative once it is terminal.
     *
     * [reason] defaults to `"cancelled"` -- an ordinary cancel, from
     * [com.danjjohnson.compress_video.Compression.cancel] or [cancelAll] on plugin detach.
     * [ForegroundServiceHost.onTimeout] (D-09) is the only other call site, passing
     * `"interrupted"` for the system's own six-hour foreground-service quota expiry, which the
     * typed error the suspended `compress()` call throws then names as retryable.
     */
    fun cancel(
        jobId: String,
        reason: String = "cancelled",
    ) {
        val job = jobs[jobId] ?: return
        if (job.cancelled || job.terminal) return
        job.cancelled = true
        job.mainHandler.removeCallbacks(job.progressRunnable)
        job.cancelTransformer()
        PluginFiles.quietDelete(job.tempFile)
        jobs.remove(jobId)
        job.onCancelled(reason)
    }

    /** Cancels every live job -- used on plugin detach so no job outlives the engine (D-17). */
    fun cancelAll() {
        for (jobId in jobs.keys.toList()) {
            cancel(jobId)
        }
        // Also clears any completed-but-unconsumed result deferreds (D-17): a background-isolate
        // job's caller that never got around to calling awaitCompressResult should not keep this
        // plugin's own map entries alive past detach.
        resultDeferreds.clear()
    }

    /**
     * Canonical paths of every live job's temp output file -- used by [PluginFiles.sweep] to
     * skip a file a still-running job is currently writing to, even when `clearCache()` runs
     * mid-job (T-02-28). Must be called on the main thread, exactly like every other method
     * here.
     */
    fun liveTempFilePaths(): Set<String> = jobs.values.map { it.tempFile.canonicalPath }.toSet()

    /**
     * One deferred per job id, resolving to that job's terminal outcome, backing
     * [CompressHostApi.awaitCompressResult] (05-02). This exists because a background isolate
     * can never receive [CompressVideoFlutterApi.onProgress]'s push
     * (`BackgroundIsolateBinaryMessenger.setMessageHandler` throws unconditionally off-root),
     * and [Compression.startCompress]'s own success paths await that push before returning --
     * so its own reply can never reach a background isolate. [awaitCompressResult] reads the
     * SAME outcome from here instead, a path that never depends on any Dart-side handler.
     *
     * Pre-created via [resultDeferredFor] (`getOrPut`) the moment a job starts, BEFORE any
     * async work runs, specifically to close the race where the job finishes (and calls
     * [completeResult]) before a caller ever calls [awaitCompressResult] for it -- confirmed
     * live during 05-02 that this is not a theoretical race: a cheap clip's real compression
     * completed in ~220ms.
     *
     * Retention note: a job whose caller never calls [awaitCompressResult] (the normal
     * root-isolate path, which reads the result straight from [Compression.startCompress]'s own
     * reply instead) leaves its completed deferred in this map until [cancelAll] runs (plugin
     * detach) -- a small, bounded object per job, not reclaimed proactively. Accepted for 05-02
     * rather than adding a time-based eviction policy: unlike [jobs] (which holds a live
     * `Transformer`/temp file), a stale entry here is one small completed [CompletableDeferred]
     * wrapping a value already reported once, not a resource leak in the traditional sense.
     */
    private val resultDeferreds = LinkedHashMap<String, CompletableDeferred<Result<CompressResultMessage>>>()

    /**
     * Returns (creating on first call for [jobId]) the deferred that will resolve to [jobId]'s
     * terminal outcome. Safe to call from either [Compression.startCompress] (to pre-register
     * before the job's own async work starts) or [Compression.awaitCompressResult] (to await
     * it) -- both run on the main thread, so `getOrPut` here is not racing itself.
     */
    fun resultDeferredFor(jobId: String): CompletableDeferred<Result<CompressResultMessage>> =
        resultDeferreds.getOrPut(jobId) { CompletableDeferred() }

    /**
     * Completes [jobId]'s result deferred with [result] -- a no-op if it is already completed,
     * since both a `TransformerEngine.compress()` success branch (called BEFORE the blocking
     * onProgress push) and `Compression.startCompress`'s own outer catch-all (for every
     * exception path, none of which block on a push) may independently try to complete the same
     * job's outcome; whichever reaches it first wins, and it is always the same value either way.
     */
    fun completeResult(
        jobId: String,
        result: Result<CompressResultMessage>,
    ) {
        val deferred = resultDeferredFor(jobId)
        if (!deferred.isCompleted) {
            deferred.complete(result)
        }
    }

    /** Forgets [jobId]'s result deferred once consumed by [awaitCompressResult]. */
    fun forgetResult(jobId: String) {
        resultDeferreds.remove(jobId)
    }
}
