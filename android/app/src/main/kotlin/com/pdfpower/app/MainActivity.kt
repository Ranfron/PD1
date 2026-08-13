package com.pdfpower.app

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger

        val paddleChannel = MethodChannel(messenger, "com.pdfpower.app/paddle_vl")
        paddleChannel.setMethodCallHandler(PaddleVLBridge(paddleChannel))

        MethodChannel(messenger, "com.pdfpower.app/mupdf")
            .setMethodCallHandler(MuPdfBridge())
    }
}
