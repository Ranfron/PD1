package com.pdfpower.app.scanner

/** Loads the OpenCV native library shipped by the official Maven AAR. */
object OpenCvSupport {
    @Volatile private var loaded = false

    fun ensureLoaded(): Boolean {
        if (loaded) return true
        return try {
            System.loadLibrary("opencv_java4")
            loaded = true
            true
        } catch (_: Throwable) {
            false
        }
    }
}
