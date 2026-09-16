package com.danjjohnson.compress_video

import android.content.Context
import android.os.Handler
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.BinaryMessenger
import org.mockito.Mockito
import java.io.File
import kotlin.test.Test
import kotlin.test.assertFalse
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
}
