package com.danjjohnson.compress_video

import io.flutter.embedding.engine.plugins.FlutterPlugin

/** CompressVideoPlugin */
class CompressVideoPlugin : FlutterPlugin {
    override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        val probe = Probe(flutterPluginBinding.applicationContext)
        ProbeHostApi.setUp(flutterPluginBinding.binaryMessenger, probe)
        ThumbnailHostApi.setUp(
            flutterPluginBinding.binaryMessenger,
            Thumbnails(flutterPluginBinding.applicationContext),
        )

        val flutterApi = CompressVideoFlutterApi(flutterPluginBinding.binaryMessenger)
        CompressHostApi.setUp(
            flutterPluginBinding.binaryMessenger,
            Compression(flutterPluginBinding.applicationContext, probe, flutterApi),
        )
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        // Every live job's Transformer is confined to the main Looper (D-17); cancelling here
        // -- still on the main thread during plugin detach, and BEFORE the host API
        // registrations below are cleared (T-02-25) -- stops each one and deletes its partial
        // output before the engine that would otherwise drive it disappears.
        JobRegistry.cancelAll()
        ProbeHostApi.setUp(binding.binaryMessenger, null)
        ThumbnailHostApi.setUp(binding.binaryMessenger, null)
        CompressHostApi.setUp(binding.binaryMessenger, null)
    }
}
