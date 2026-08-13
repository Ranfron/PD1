package com.pdfpower.app.scanner

/**
 * Stabilizes document corners across frames before auto-capture.
 * Requires [stableMs] continuous detection with low corner jitter.
 */
class AutoCaptureController(
    private val stableMs: Long = 700L,
    private val maxJitterPx: Float = 18f
) {
    private var lastQuad: Quad? = null
    private var stableSince: Long = 0L
    private var armed = false

    fun reset() {
        lastQuad = null
        stableSince = 0L
        armed = false
    }

    /**
     * @return true when document is stable long enough to capture
     */
    fun onDetection(quad: Quad?, now: Long = System.currentTimeMillis()): Boolean {
        if (quad == null) {
            reset()
            return false
        }
        val prev = lastQuad
        if (prev == null) {
            lastQuad = quad
            stableSince = now
            armed = false
            return false
        }
        val jitter = cornerJitter(prev, quad)
        if (jitter > maxJitterPx) {
            lastQuad = quad
            stableSince = now
            armed = false
            return false
        }
        lastQuad = quad
        if (!armed && now - stableSince >= stableMs) {
            armed = true
            return true
        }
        return false
    }

    private fun cornerJitter(a: Quad, b: Quad): Float {
        var maxD = 0f
        for (i in 0 until 4) {
            val dx = a.points[i * 2] - b.points[i * 2]
            val dy = a.points[i * 2 + 1] - b.points[i * 2 + 1]
            val d = kotlin.math.hypot(dx.toDouble(), dy.toDouble()).toFloat()
            if (d > maxD) maxD = d
        }
        return maxD
    }
}
