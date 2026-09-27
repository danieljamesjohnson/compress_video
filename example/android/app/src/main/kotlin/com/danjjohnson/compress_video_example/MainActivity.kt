package com.danjjohnson.compress_video_example

import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * A hand-written `MethodChannel` is otherwise forbidden in this repository (BULD-03) -- it is
 * acceptable here, and only here, because `example/` is deliberately outside the plugin's own
 * channel-plumbing scope (`lib/`, `android/src/main/`, `darwin/compress_video/Sources/`; CI's
 * own grep step enumerates exactly those three directories). This channel exists solely so
 * `example/integration_test/jobs_background_test.dart` can background this app mid-encode
 * (`moveTaskToBack`) and read the emulator's real API level (`apiLevel`), so its assertions
 * come from the platform rather than from an assumption about which image CI happens to run
 * (05-03-PLAN.md task 2).
 */
class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL_NAME)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "moveTaskToBack" -> result.success(moveTaskToBack(true))
                    "apiLevel" -> result.success(Build.VERSION.SDK_INT)
                    else -> result.notImplemented()
                }
            }
    }

    private companion object {
        const val CHANNEL_NAME = "compress_video_example/backgrounding"
    }
}
