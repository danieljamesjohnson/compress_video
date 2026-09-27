package com.danjjohnson.compress_video

import android.os.Handler
import java.io.File
import kotlin.test.Test
import kotlin.test.assertFalse
import kotlin.test.assertTrue
import org.mockito.Mockito.mock

/**
 * CR-02: `Compression.awaitCompressResult` must fail with a typed [CompressVideoError] --
 * never hang forever -- for a jobId nothing ever started, or one whose result was already
 * consumed by an earlier call. [Compression] itself asserts the main Looper before doing
 * anything, which throws in a plain JVM unit test (no Robolectric here, see
 * [CompressVideoPluginTest]'s own doc comment for the same constraint), so this suite exercises
 * the pure [JobRegistry] bookkeeping ([JobRegistry.isKnownJobId]/[JobRegistry.isConsumedJobId])
 * that guard reads directly, exactly as [ForegroundServiceHostTest] exercises
 * [ForegroundServiceHost.Ref] rather than the real `Service`.
 */
internal class JobRegistryTest {
    @Test
    fun isKnownJobId_isFalseForAJobIdNothingEverStarted() {
        assertFalse(
            JobRegistry.isKnownJobId("0-1111111111111111"),
            "a jobId resultDeferredFor was never called for must not be known",
        )
    }

    @Test
    fun isKnownJobId_isTrueOnceResultDeferredForHasRegisteredIt() {
        val jobId = "0-2222222222222222"

        JobRegistry.resultDeferredFor(jobId)

        assertTrue(JobRegistry.isKnownJobId(jobId), "resultDeferredFor must register jobId as known")
        assertFalse(JobRegistry.isConsumedJobId(jobId), "a job whose result was never forgotten is not consumed")

        JobRegistry.forgetResult(jobId) // cleanup: restore registry state for other tests
    }

    @Test
    fun isConsumedJobId_isTrueOnceForgetResultHasRun() {
        val jobId = "0-3333333333333333"
        JobRegistry.completeResult(jobId, Result.failure(RuntimeException("test outcome")))

        JobRegistry.forgetResult(jobId)

        assertTrue(
            JobRegistry.isConsumedJobId(jobId),
            "a second awaitCompressResult call for this jobId must see it as already consumed, " +
                "rather than hanging on a freshly manufactured deferred",
        )
        assertTrue(JobRegistry.isKnownJobId(jobId), "a consumed job remains known, just also consumed")
    }

    /**
     * D-17/CR-02: [JobRegistry.cancelAll] (plugin detach) resets ALL of a job's bookkeeping, not
     * just its live [JobRegistry.jobs] entry -- otherwise a jobId from before detach could keep
     * reporting a stale "already consumed" outcome indefinitely instead of becoming unknown.
     */
    @Test
    fun cancelAll_resetsKnownAndConsumedJobIdBookkeeping() {
        val knownJobId = "0-4444444444444444"
        val consumedJobId = "0-5555555555555555"
        JobRegistry.resultDeferredFor(knownJobId)
        JobRegistry.completeResult(consumedJobId, Result.failure(RuntimeException("test outcome")))
        JobRegistry.forgetResult(consumedJobId)

        JobRegistry.cancelAll()

        assertFalse(JobRegistry.isKnownJobId(knownJobId), "cancelAll must reset known-job bookkeeping")
        assertFalse(JobRegistry.isConsumedJobId(consumedJobId), "cancelAll must reset consumed-job bookkeeping")
    }

    /**
     * WR-01 regression: a job that is genuinely LIVE (a real [JobRegistry.LiveJob], registered
     * via [JobRegistry.register] exactly like [TransformerEngine.attemptExport] does) at the
     * moment [JobRegistry.cancelAll] runs must not have its bookkeeping resurrected once its
     * cancellation's belated completion -- the suspended `Compression.startCompress` call's own
     * catch block calling [JobRegistry.completeResult], which in production only runs on a LATER
     * main-Looper message than `cancelAll()`'s own call stack -- actually arrives. The
     * pre-existing `cancelAll_resetsKnownAndConsumedJobIdBookkeeping` test above cannot catch this
     * class of bug: it never registers a live job, so there is no [JobRegistry.LiveJob.onCancelled]
     * callback to race and no belated [JobRegistry.completeResult] call to resurrect anything.
     *
     * [Handler]/[Runnable] are mocked with Mockito rather than constructed for real: this is a
     * plain JVM test with no Robolectric shadow layer, so a real `Handler(Looper.getMainLooper())`
     * would throw against the unmocked Android stub jar the instant [JobRegistry.cancel] called
     * `removeCallbacks` on it. A Mockito mock never runs the real Android implementation, so it is
     * simply a no-op here -- [JobRegistry] itself has no other Android-framework dependency
     * ([JobRegistry]'s own class doc comment).
     */
    @Test
    fun cancelAll_doesNotResurrectBookkeeping_forALiveJobsBelatedCancellationCompletion() {
        val jobId = "0-6666666666666666"
        val tempFile = File.createTempFile("jobregistrytest", ".tmp")
        val mainHandler = mock(Handler::class.java)
        val progressRunnable = Runnable {}
        // Mirrors TransformerEngine.attemptExport's own onCancelled wiring exactly: recording the
        // reason is the ONLY thing the real onCancelled callback triggers synchronously (it
        // completes a CompletableDeferred there) -- it does not itself call completeResult. The
        // suspended coroutine awaiting that deferred is what eventually (later) calls
        // completeResult, simulated explicitly below rather than via getCompleted() (experimental
        // API) on a real CompletableDeferred.
        var cancelledReason: String? = null
        try {
            JobRegistry.register(
                jobId,
                JobRegistry.LiveJob(
                    cancelTransformer = {},
                    tempFile = tempFile,
                    mainHandler = mainHandler,
                    progressRunnable = progressRunnable,
                    onCancelled = { reason -> cancelledReason = reason },
                ),
            )
            JobRegistry.resultDeferredFor(jobId) // pre-registration, mirrors Compression.startCompress

            JobRegistry.cancelAll()

            assertFalse(
                JobRegistry.isKnownJobId(jobId),
                "cancelAll must reset known-job bookkeeping immediately, before the cancelled " +
                    "job's own completion has unwound",
            )
            assertTrue(cancelledReason != null, "cancelAll's cancel() call must have invoked onCancelled")

            // The belated resumption: mirrors Compression.startCompress's catch block calling
            // completeResult once the real onCancelled's CompletableDeferred completion actually
            // resumes the suspended coroutine awaiting it -- on a LATER main-Looper message than
            // cancelAll()'s own call stack, per Pigeon's non-.immediate Dispatchers.Main dispatch.
            JobRegistry.completeResult(jobId, Result.failure(RuntimeException(cancelledReason)))

            assertFalse(
                JobRegistry.isKnownJobId(jobId),
                "a belated completeResult call for a job cancelAll() already tore down must not " +
                    "resurrect knownJobIds bookkeeping (WR-01)",
            )
        } finally {
            tempFile.delete()
        }
    }
}
