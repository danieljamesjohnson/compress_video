package com.danjjohnson.compress_video

import android.os.Handler
import androidx.media3.transformer.Transformer
import java.io.File

/**
 * Main-thread-confined registry of live compression jobs, keyed by job id.
 *
 * Every method here must be called from the main thread -- the same thread every [Transformer]
 * in this plugin is built and driven on ([TransformerEngine], 02-RESEARCH.md Pattern 1).
 * Main-thread confinement is the synchronization here: there is no lock and no cross-thread
 * mutable state.
 */
object JobRegistry {
    /**
     * One job's live state: the [Transformer] driving it, the temp file it is writing to, how
     * to stop its progress polling, and how to resolve it when cancelled from outside its own
     * completion callback.
     */
    class LiveJob(
        val transformer: Transformer,
        val tempFile: File,
        val mainHandler: Handler,
        val progressRunnable: Runnable,
        val onCancelled: () -> Unit,
    ) {
        internal var cancelled: Boolean = false
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
     * Cancels the job identified by [jobId]: stops its progress polling, cancels its
     * [Transformer], deletes its temp output file, forgets it, and invokes its
     * [LiveJob.onCancelled] callback so the suspended `startCompress` call can fail with a
     * typed cancelled error. A no-op if [jobId] is unknown or already cancelled.
     */
    fun cancel(jobId: String) {
        val job = jobs[jobId] ?: return
        if (job.cancelled) return
        job.cancelled = true
        job.mainHandler.removeCallbacks(job.progressRunnable)
        job.transformer.cancel()
        PluginFiles.quietDelete(job.tempFile)
        jobs.remove(jobId)
        job.onCancelled()
    }

    /** Cancels every live job -- used on plugin detach so no job outlives the engine (D-17). */
    fun cancelAll() {
        for (jobId in jobs.keys.toList()) {
            cancel(jobId)
        }
    }
}
