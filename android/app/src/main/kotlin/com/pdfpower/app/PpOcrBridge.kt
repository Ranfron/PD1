package com.pdfpower.app

import android.os.Handler
import android.os.Looper
import com.pdfpower.app.ocr.PpOcrEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.Executors

/**
 * Flutter MethodChannel bridge for real PP-OCR (ONNX Runtime).
 * DET: PP-OCRv6 Medium · REC: devanagari_PP-OCRv5_mobile_rec
 */
class PpOcrBridge(private val channel: MethodChannel) :
    MethodChannel.MethodCallHandler {

    private val executor = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    private val engine = PpOcrEngine()

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "nativeReady" -> result.success(true)

            "isReady" -> result.success(engine.isReady())

            "initialize" -> {
                val det = call.argument<String>("detPath")
                val rec = call.argument<String>("recPath")
                val dict = call.argument<String>("dictPath")
                if (det.isNullOrBlank() || rec.isNullOrBlank() || dict.isNullOrBlank() ||
                    !File(det).exists() || !File(rec).exists() || !File(dict).exists()
                ) {
                    result.success(false)
                    return
                }
                executor.execute {
                    val ok = try {
                        engine.load(det, rec, dict)
                    } catch (_: Throwable) {
                        false
                    }
                    main.post { result.success(ok) }
                }
            }

            "processImage" -> {
                val imagePath = call.argument<String>("imagePath") ?: ""
                executor.execute {
                    val text = try {
                        if (!engine.isReady()) ""
                        else engine.processPlainText(imagePath)
                    } catch (_: Throwable) {
                        ""
                    }
                    main.post { result.success(text) }
                }
            }

            "analyzePage" -> {
                val page = call.argument<Int>("page") ?: 1
                val imagePath = call.argument<String>("imagePath") ?: ""
                executor.execute {
                    val json = try {
                        if (engine.isReady() && imagePath.isNotBlank()) {
                            engine.analyzeImage(imagePath, page)
                        } else {
                            """{"page":$page,"engine":"not_ready","objects":[]}"""
                        }
                    } catch (t: Throwable) {
                        """{"page":$page,"engine":"error","objects":[]}"""
                    }
                    main.post { result.success(json) }
                }
            }

            "unload" -> {
                executor.execute {
                    try {
                        engine.unload()
                    } catch (_: Throwable) {
                    }
                    main.post { result.success(null) }
                }
            }

            else -> result.notImplemented()
        }
    }
}
