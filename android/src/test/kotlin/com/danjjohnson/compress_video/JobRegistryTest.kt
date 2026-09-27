package com.danjjohnson.compress_video

import kotlin.test.Test
import kotlin.test.assertFalse
import kotlin.test.assertTrue

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
}
