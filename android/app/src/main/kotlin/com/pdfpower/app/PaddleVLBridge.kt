package com.pdfpower.app

import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.Executors

/**
 * Native bridge for optional PaddleOCR-VL-1.6 (llama.cpp + GGUF).
 *
 * Current build ships a safe stub:
 *  - isReady / initialize report availability based on model files only
 *  - processImage returns empty until real llama.cpp is linked
 *
 * To enable real inference:
 *  1. Add llama.cpp (or your VL runtime) under src/main/cpp
 *  2. Wire CMakeLists.txt + System.loadLibrary
 *  3. Implement native processImage with model + mmproj paths
 */
class PaddleVLBridge(private val channel: MethodChannel) :
    MethodChannel.MethodCallHandler {

    private val executor = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())

    @Volatile private var modelPath: String? = null
    @Volatile private var mmprojPath: String? = null
    @Volatile private var loaded = false

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "isReady" -> {
                result.success(loaded && modelPath != null && mmprojPath != null)
            }
            "initialize" -> {
                val model = call.argument<String>("modelPath")
                val mmproj = call.argument<String>("mmprojPath")
                if (model.isNullOrBlank() || mmproj.isNullOrBlank()) {
                    result.success(false)
                    return
                }
                if (!File(model).exists() || !File(mmproj).exists()) {
                    result.success(false)
                    return
                }
                executor.execute {
                    // TODO: native loadModel(model, mmproj)
                    modelPath = model
                    mmprojPath = mmproj
                    loaded = true
                    main.post { result.success(true) }
                }
            }
            "processImage" -> {
                val imagePath = call.argument<String>("imagePath")
                if (!loaded || imagePath.isNullOrBlank() || !File(imagePath).exists()) {
                    result.success("")
                    return
                }
                executor.execute {
                    // TODO: call native OCR with modelPath + mmprojPath + imagePath
                    // Until llama.cpp is linked, return empty → Flutter falls back to ML Kit
                    val text = ""
                    main.post { result.success(text) }
                }
            }
            "unload" -> {
                executor.execute {
                    // TODO: native unload
                    loaded = false
                    modelPath = null
                    mmprojPath = null
                    main.post { result.success(null) }
                }
            }
            else -> result.notImplemented()
        }
    }
}
