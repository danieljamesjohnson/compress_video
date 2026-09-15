package com.danjjohnson.compress_video

import io.flutter.embedding.engine.plugins.FlutterPlugin

/** CompressVideoPlugin */
class CompressVideoPlugin : FlutterPlugin {
    override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        ProbeHostApi.setUp(
            flutterPluginBinding.binaryMessenger,
            Probe(flutterPluginBinding.applicationContext),
        )
        ThumbnailHostApi.setUp(
            flutterPluginBinding.binaryMessenger,
            Thumbnails(flutterPluginBinding.applicationContext),
        )
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        ProbeHostApi.setUp(binding.binaryMessenger, null)
        ThumbnailHostApi.setUp(binding.binaryMessenger, null)
    }
}
