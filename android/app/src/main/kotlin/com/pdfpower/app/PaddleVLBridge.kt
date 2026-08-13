package com.pdfpower.app

import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.Executors

class PaddleVLBridge(private val channel: MethodChannel) :
    MethodChannel.MethodCallHandler {

    private val executor = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())

    companion object {
        private var libLoaded = false

        init {
            try {
                System.loadLibrary("paddle_vl_stub")
                libLoaded = true
            } catch (_: UnsatisfiedLinkError) {
                libLoaded = false
            }
        }

        @JvmStatic external fun nativePing(): String
        @JvmStatic external fun nativeLoadModel(modelPath: String, mmprojPath: String): Boolean
        @JvmStatic external fun nativeUnload()
        @JvmStatic external fun nativeIsReady(): Boolean
        @JvmStatic external fun nativeIsLoaded(): Boolean
        @JvmStatic external fun nativeAnalyzePage(imagePath: String, page: Int): String
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "nativeReady" -> result.success(libLoaded)

            "isReady" -> {
                if (!libLoaded) {
                    result.success(false)
                    return
                }
                executor.execute {
                    val ok = try { nativeIsReady() } catch (_: Throwable) { false }
                    main.post { result.success(ok) }
                }
            }

            "initialize" -> {
                val model = call.argument<String>("modelPath")
                val mmproj = call.argument<String>("mmprojPath")
                if (!libLoaded || model.isNullOrBlank() || mmproj.isNullOrBlank() ||
                    !File(model).exists() || !File(mmproj).exists()
                ) {
                    result.success(false)
                    return
                }
                executor.execute {
                    val ok = try {
                        nativeLoadModel(model, mmproj)
                    } catch (t: Throwable) {
                        false
                    }
                    main.post { result.success(ok) }
                }
            }

            "processImage" -> {
                val imagePath = call.argument<String>("imagePath") ?: ""
                executor.execute {
                    val text = try {
                        if (!libLoaded || !nativeIsReady()) ""
                        else {
                            val json = nativeAnalyzePage(imagePath, 1)
                            extractPlainText(json)
                        }
                    } catch (_: Throwable) { "" }
                    main.post { result.success(text) }
                }
            }

            "analyzePage" -> {
                val page = call.argument<Int>("page") ?: 1
                val imagePath = call.argument<String>("imagePath") ?: ""
                executor.execute {
                    val json = try {
                        if (libLoaded && nativeIsReady()) {
                            nativeAnalyzePage(imagePath, page)
                        } else {
                            """{"page":$page,"engine":"not_ready","objects":[]}"""
                        }
                    } catch (_: Throwable) {
                        """{"page":$page,"engine":"error","objects":[]}"""
                    }
                    main.post { result.success(json) }
                }
            }

            "unload" -> {
                executor.execute {
                    try { if (libLoaded) nativeUnload() } catch (_: Throwable) {}
                    main.post { result.success(null) }
                }
            }

            else -> result.notImplemented()
        }
    }

    private fun extractPlainText(json: String): String {
        val re = Regex("\"text\"\\s*:\\s*\"((?:\\\\.|[^\"])*)\"")
        return re.findAll(json).map { it.groupValues[1] }.joinToString("\n")
    }
}
