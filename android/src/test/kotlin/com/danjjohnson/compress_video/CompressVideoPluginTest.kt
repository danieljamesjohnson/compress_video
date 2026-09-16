package com.danjjohnson.compress_video

import android.content.Context
import android.os.Handler
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.BinaryMessenger
import org.mockito.Mockito
import java.io.File
import kotlin.test.Test
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

/**
 * The template's `getPlatformVersion` MethodChannel handler is gone; this plugin now registers
 * [Probe] as the generated [ProbeHostApi]. This test asserts attach/detach lifecycle wiring
 * doesn't throw -- the actual [ProbeHostApi] behaviour is covered by [MediaMathTest] and
 * [ArgumentsTest] (pure logic) and by the emulator integration test (end to end).
 */
internal class CompressVideoPluginTest {
    private fun mockBinding(): FlutterPlugin.FlutterPluginBinding {
        val binding = Mockito.mock(FlutterPlugin.FlutterPluginBinding::class.java)
        val messenger = Mockito.mock(BinaryMessenger::class.java)
        val context = Mockito.mock(Context::class.java)
        Mockito.`when`(binding.binaryMessenger).thenReturn(messenger)
        Mockito.`when`(binding.applicationContext).thenReturn(context)
        return binding
    }

    @Test
    fun onAttachedAndDetachedFromEngine_doesNotThrow() {
        val plugin = CompressVideoPlugin()
        val binding = mockBinding()

        plugin.onAttachedToEngine(binding)
        plugin.onDetachedFromEngine(binding)
    }

    /**
     * T-02-25: detaching cancels every live job -- through the registry, deleting each job's
     * partial output file -- before the host API registrations are cleared.
     */
    @Test
    fun onDetachedFromEngine_cancelsEveryLiveJobAndEmptiesTheRegistry() {
        val plugin = CompressVideoPlugin()
        val binding = mockBinding()
        plugin.onAttachedToEngine(binding)

        val jobId = "0-aaaaaaaaaaaaaaaa"
        val partialOutput = File.createTempFile("compress_video_plugin_test", ".tmp")
        var cancelTransformerInvoked = false
        var onCancelledInvoked = false
        JobRegistry.register(
            jobId,
            JobRegistry.LiveJob(
                cancelTransformer = { cancelTransformerInvoked = true },
                tempFile = partialOutput,
                mainHandler = Mockito.mock(Handler::class.java),
                progressRunnable = Runnable {},
                onCancelled = { onCancelledInvoked = true },
            ),
        )

        plugin.onDetachedFromEngine(binding)

        assertNull(JobRegistry.find(jobId), "the registry must be empty after detach")
        assertTrue(cancelTransformerInvoked, "the job's cancelTransformer callback must have run")
        assertTrue(onCancelledInvoked, "the job's onCancelled callback must have run")
        assertFalse(partialOutput.exists(), "the job's partial output must be deleted")
    }

    /** A registry with no live jobs detaches cleanly -- cancelAll on an empty map is a no-op. */
    @Test
    fun onDetachedFromEngine_withNoLiveJobs_detachesCleanly() {
        val plugin = CompressVideoPlugin()
        val binding = mockBinding()
        plugin.onAttachedToEngine(binding)

        plugin.onDetachedFromEngine(binding)

        assertNull(JobRegistry.find("no-such-job"))
    }

    /**
     * WR-01: a `cancel()` arriving in the window between a job's `Transformer.Listener` terminal
     * callback firing (`JobRegistry.stopPolling`, which now also marks [JobRegistry.LiveJob]
     * terminal) and the still-suspended `compress()` coroutine's own continuation calling
     * `JobRegistry.remove` must be a no-op: it must NOT invoke `cancelTransformer`, must NOT
     * delete the job's temp file, and must NOT invoke `onCancelled` -- the job's own outcome,
     * already resolved on the native side, is authoritative. This reproduces the exact ordering
     * the review found: `stopPolling` (simulating the listener callback) runs strictly before
     * `cancel` (simulating a racing caller), both before `remove` (simulating the coroutine's
     * own resumed cleanup).
     */
    @Test
    fun cancel_afterStopPollingMarksJobTerminal_isANoOp() {
        val jobId = "0-bbbbbbbbbbbbbbbb"
        val tempFile = File.createTempFile("compress_video_plugin_test_wr01", ".tmp")
        var cancelTransformerInvoked = false
        var onCancelledInvoked = false
        JobRegistry.register(
            jobId,
            JobRegistry.LiveJob(
                cancelTransformer = { cancelTransformerInvoked = true },
                tempFile = tempFile,
                mainHandler = Mockito.mock(Handler::class.java),
                progressRunnable = Runnable {},
                onCancelled = { onCancelledInvoked = true },
            ),
        )

        // Simulates Transformer.Listener.onCompleted/onError firing first and resolving the
        // job's outcome, exactly as TransformerEngine does before the suspended compress() call
        // has resumed.
        JobRegistry.stopPolling(jobId)

        // Simulates a cancel() call racing in during that window -- the bug this fix closes.
        JobRegistry.cancel(jobId)

        assertFalse(
            cancelTransformerInvoked,
            "cancel() must not cancel an already-terminal job's Transformer",
        )
        assertFalse(
            onCancelledInvoked,
            "cancel() must not invoke onCancelled for an already-terminal job",
        )
        assertTrue(
            tempFile.exists(),
            "cancel() must not delete an already-terminal job's temp file -- the coroutine may " +
                "still be about to move it into place",
        )
        assertNotNull(
            JobRegistry.find(jobId),
            "an already-terminal job must remain registered until its own compress() " +
                "coroutine calls remove(), not be forgotten by a no-op cancel()",
        )

        // Simulates the coroutine's own resumed cleanup, restoring registry state for other
        // tests.
        JobRegistry.remove(jobId)
        tempFile.delete()
    }
}
