package com.danjjohnson.compress_video

import android.content.Context
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.BinaryMessenger
import org.mockito.Mockito
import kotlin.test.Test

/**
 * The template's `getPlatformVersion` MethodChannel handler is gone; this plugin now registers
 * [Probe] as the generated [ProbeHostApi]. This test asserts attach/detach lifecycle wiring
 * doesn't throw -- the actual [ProbeHostApi] behaviour is covered by [MediaMathTest] and
 * [ArgumentsTest] (pure logic) and by the emulator integration test (end to end).
 */
internal class CompressVideoPluginTest {
    @Test
    fun onAttachedAndDetachedFromEngine_doesNotThrow() {
        val plugin = CompressVideoPlugin()
        val binding = Mockito.mock(FlutterPlugin.FlutterPluginBinding::class.java)
        val messenger = Mockito.mock(BinaryMessenger::class.java)
        val context = Mockito.mock(Context::class.java)
        Mockito.`when`(binding.binaryMessenger).thenReturn(messenger)
        Mockito.`when`(binding.applicationContext).thenReturn(context)

        plugin.onAttachedToEngine(binding)
        plugin.onDetachedFromEngine(binding)
    }
}
