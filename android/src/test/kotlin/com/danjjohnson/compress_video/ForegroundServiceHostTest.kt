package com.danjjohnson.compress_video

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue
import kotlin.test.fail

/**
 * Plain JVM tests for [ForegroundServiceHost.Ref], the ref-counted bookkeeping the real
 * `ForegroundServiceHost` service delegates to. No Android framework type is exercised here --
 * [ForegroundServiceHost.Ref] has none -- so this suite proves attach/detach counting and the
 * whole `onTimeout` contract (D-09, T-05-13) with no Android test-framework shadowing layer, no
 * real `Service` instance and no emulator, exactly as [JobRegistry] and [ErrorMapping] are
 * tested elsewhere in this package.
 */
internal class ForegroundServiceHostTest {
    @Test
    fun twoAttachesAndOneDetach_leaveOneJobHostedAndNotStopped() {
        val ref = ForegroundServiceHost.Ref()

        ref.attach("job-a")
        ref.attach("job-b")
        val shouldStop = ref.detach("job-a")

        assertFalse(shouldStop, "one job is still hosted -- the service must not stop")
        assertEquals(1, ref.hostedCount)
    }

    @Test
    fun theSecondDetach_stopsTheService() {
        val ref = ForegroundServiceHost.Ref()

        ref.attach("job-a")
        ref.attach("job-b")
        ref.detach("job-a")
        val shouldStop = ref.detach("job-b")

        assertTrue(shouldStop, "the last hosted job detaching must signal a stop")
        assertEquals(0, ref.hostedCount)
    }

    @Test
    fun detachingAnUnknownJobId_isANoOp() {
        val ref = ForegroundServiceHost.Ref()
        ref.attach("job-a")

        val shouldStop = ref.detach("no-such-job")

        assertFalse(shouldStop)
        assertEquals(1, ref.hostedCount, "the unknown detach must not touch the real hosted job")
    }

    /**
     * T-05-13: the whole `onTimeout` contract, proven with injected test doubles rather than by
     * observing a real `Service` -- cancel every currently hosted job with the reason the real
     * override always passes ([ForegroundServiceHost.REASON_INTERRUPTED]), then unconditionally
     * stop.
     */
    @Test
    fun onTimeout_withHostedJobs_cancelsEachWithTheInterruptedReasonAndStops() {
        val ref = ForegroundServiceHost.Ref()
        ref.attach("job-a")
        ref.attach("job-b")

        val cancelledJobIds = mutableListOf<String>()
        var stopped = false
        ref.onTimeout(
            cancel = { jobId -> cancelledJobIds.add(jobId) },
            stop = { stopped = true },
        )

        assertEquals(setOf("job-a", "job-b"), cancelledJobIds.toSet())
        assertTrue(stopped, "onTimeout must stop the service -- omitting this is the documented ANR")
        assertEquals(0, ref.hostedCount, "onTimeout must forget every job it cancelled")
    }

    /**
     * MUST NOT return from `onTimeout` without stopping (05-RESEARCH.md Anti-Patterns): even
     * with nothing hosted, the override still has to call `stopSelf`.
     */
    @Test
    fun onTimeout_withNoHostedJobs_stillStops() {
        val ref = ForegroundServiceHost.Ref()

        var stopped = false
        ref.onTimeout(cancel = { fail("no job is hosted; cancel must not be invoked") }, stop = { stopped = true })

        assertTrue(stopped, "onTimeout must stop the service even with zero hosted jobs")
    }
}
