package com.pdfpower.app.scanner

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.io.FileOutputStream
import java.util.concurrent.Executors

/**
 * Native scanner pipeline (Camera frames / still images):
 * detect → stabilize → perspective crop → enhance
 *
 * Live CameraX preview is driven from Flutter `camera` plugin or a
 * PlatformView; this bridge handles still-image / captured-frame processing.
 */
class ScannerBridge : MethodChannel.MethodCallHandler {

    private val executor = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    private val detector = DocumentDetector()
    private val autoCapture = AutoCaptureController()

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "detectDocument" -> {
                val path = call.argument<String>("imagePath") ?: ""
                val modeStr = call.argument<String>("mode") ?: "document"
                val mode = if (modeStr == "card") ScanMode.CARD else ScanMode.DOCUMENT
                executor.execute {
                    val json = try {
                        val bmp = BitmapFactory.decodeFile(path)
                        if (bmp == null) {
                            """{"found":false}"""
                        } else {
                            val quad = detector.detect(bmp, mode)
                            if (!bmp.isRecycled) bmp.recycle()
                            if (quad == null) {
                                """{"found":false}"""
                            } else {
                                JSONObject().apply {
                                    put("found", true)
                                    put("points", JSONArray(quad.points.toList()))
                                    put("area", quad.approxArea())
                                }.toString()
                            }
                        }
                    } catch (t: Throwable) {
                        """{"found":false,"error":"${t.message}"}"""
                    }
                    main.post { result.success(json) }
                }
            }

            "processScan" -> {
                val path = call.argument<String>("imagePath") ?: ""
                val modeStr = call.argument<String>("mode") ?: "document"
                val enhance = call.argument<Boolean>("enhance") ?: true
                val bw = call.argument<Boolean>("bw") ?: false
                val outDir = call.argument<String>("outDir") ?: ""
                val mode = if (modeStr == "card") ScanMode.CARD else ScanMode.DOCUMENT
                executor.execute {
                    val outPath = try {
                        val bmp = BitmapFactory.decodeFile(path)
                            ?: throw IllegalStateException("decode failed")
                        val quad = detector.detect(bmp, mode)
                            ?: Quad(
                                floatArrayOf(
                                    0f, 0f,
                                    bmp.width.toFloat(), 0f,
                                    bmp.width.toFloat(), bmp.height.toFloat(),
                                    0f, bmp.height.toFloat()
                                )
                            )
                        var out = PerspectiveCorrector.correct(bmp, quad, enhance)
                        if (bw) {
                            val bwBmp = PerspectiveCorrector.toBlackWhite(out)
                            if (out !== bwBmp && !out.isRecycled) out.recycle()
                            out = bwBmp
                        }
                        if (!bmp.isRecycled) bmp.recycle()
                        val dir = if (outDir.isNotBlank()) File(outDir) else File(path).parentFile
                        dir?.mkdirs()
                        val dest = File(dir, "scan_${System.currentTimeMillis()}.jpg")
                        FileOutputStream(dest).use { fos ->
                            out.compress(Bitmap.CompressFormat.JPEG, 92, fos)
                        }
                        if (!out.isRecycled) out.recycle()
                        dest.absolutePath
                    } catch (t: Throwable) {
                        null
                    }
                    main.post { result.success(outPath) }
                }
            }

            "resetAutoCapture" -> {
                autoCapture.reset()
                result.success(null)
            }

            "checkStable" -> {
                val path = call.argument<String>("imagePath") ?: ""
                val modeStr = call.argument<String>("mode") ?: "document"
                val mode = if (modeStr == "card") ScanMode.CARD else ScanMode.DOCUMENT
                executor.execute {
                    val stable = try {
                        val bmp = BitmapFactory.decodeFile(path) ?: return@execute main.post {
                            result.success(false)
                        }
                        val quad = detector.detect(bmp, mode)
                        if (!bmp.isRecycled) bmp.recycle()
                        autoCapture.onDetection(quad)
                    } catch (_: Throwable) {
                        false
                    }
                    main.post { result.success(stable) }
                }
            }

            else -> result.notImplemented()
        }
    }
}
