package com.pdfpower.app

import com.pdfpower.app.scanner.ScannerBridge
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger

        MethodChannel(messenger, "com.pdfpower.app/pp_ocr")
            .setMethodCallHandler(PpOcrBridge(MethodChannel(messenger, "com.pdfpower.app/pp_ocr")))

        MethodChannel(messenger, "com.pdfpower.app/mupdf")
            .setMethodCallHandler(MuPdfBridge())

        MethodChannel(messenger, "com.pdfpower.app/scanner")
            .setMethodCallHandler(ScannerBridge())
    }
}
