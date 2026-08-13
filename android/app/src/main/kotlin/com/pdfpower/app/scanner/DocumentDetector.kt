package com.pdfpower.app.scanner

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import org.opencv.core.Mat
import org.opencv.core.MatOfPoint
import org.opencv.core.MatOfPoint2f
import org.opencv.core.Point
import org.opencv.core.Size
import org.opencv.imgcodecs.Imgcodecs
import org.opencv.imgproc.Imgproc
import java.io.ByteArrayOutputStream
import kotlin.math.abs
import kotlin.math.max

enum class ScanMode { DOCUMENT, CARD }

data class Quad(val points: FloatArray) {
    fun approxArea(): Float {
        var a = 0f
        for (i in 0 until 4) {
            val j = (i + 1) % 4
            a += points[i * 2] * points[j * 2 + 1]
            a -= points[j * 2] * points[i * 2 + 1]
        }
        return abs(a) / 2f
    }

    fun isValid(minArea: Float): Boolean {
        if (points.size != 8 || approxArea() < minArea) return false
        for (i in 0 until 4) {
            if (!points[i * 2].isFinite() || !points[i * 2 + 1].isFinite()) return false
        }
        return true
    }

    fun center(): Pair<Float, Float> {
        var x = 0f; var y = 0f
        for (i in 0 until 4) { x += points[i * 2]; y += points[i * 2 + 1] }
        return x / 4f to y / 4f
    }
}

/**
 * Real contour/quad document detector using OpenCV. It works on a small
 * working copy, then maps the detected four corners back to the source.
 */
class DocumentDetector {
    fun detect(src: Bitmap, mode: ScanMode = ScanMode.DOCUMENT): Quad? {
        if (src.width < 64 || src.height < 64 || !OpenCvSupport.ensureLoaded()) return null

        val jpeg = ByteArrayOutputStream().use { out ->
            src.compress(Bitmap.CompressFormat.JPEG, 88, out)
            out.toByteArray()
        }
        val input = MatOfByteCompat.decode(jpeg) ?: return null
        val work = Mat()
        try {
            val maxSide = 900.0
            val scale = minOf(1.0, maxSide / max(src.width, src.height).toDouble())
            Imgproc.resize(input, work, Size(src.width * scale, src.height * scale))

            val gray = Mat()
            val blur = Mat()
            val edges = Mat()
            val contours = ArrayList<MatOfPoint>()
            try {
                Imgproc.cvtColor(work, gray, Imgproc.COLOR_BGR2GRAY)
                Imgproc.GaussianBlur(gray, blur, Size(5.0, 5.0), 0.0)
                Imgproc.Canny(blur, edges, 50.0, 150.0)
                Imgproc.morphologyEx(edges, edges, Imgproc.MORPH_CLOSE,
                    Imgproc.getStructuringElement(Imgproc.MORPH_RECT, Size(5.0, 5.0)))
                Imgproc.findContours(edges, contours, Mat(), Imgproc.RETR_LIST, Imgproc.CHAIN_APPROX_SIMPLE)

                val imageArea = work.rows().toDouble() * work.cols().toDouble()
                val minFraction = if (mode == ScanMode.CARD) 0.05 else 0.10
                var best: Quad? = null
                var bestScore = 0.0

                for (contour in contours) {
                    val area = abs(Imgproc.contourArea(contour))
                    if (area < imageArea * minFraction) { contour.release(); continue }
                    val peri = Imgproc.arcLength(MatOfPoint2f(*contour.toArray()), true)
                    val approx = MatOfPoint2f()
                    Imgproc.approxPolyDP(MatOfPoint2f(*contour.toArray()), approx, 0.02 * peri, true)
                    val pts = approx.toArray()
                    if (pts.size != 4 || !Imgproc.isContourConvex(MatOfPoint(*pts))) { approx.release(); contour.release(); continue }
                    val ordered = orderPoints(pts)
                    val aspect = quadAspect(ordered)
                    if (!aspectAllowed(aspect, mode)) { approx.release(); contour.release(); continue }
                    val rectangularity = area / max(1.0, polygonArea(ordered))
                    val score = area * (0.55 + 0.45 * rectangularity)
                    if (score > bestScore) {
                        bestScore = score
                        best = Quad(ordered.flatMap { listOf((it.x / scale).toFloat(), (it.y / scale).toFloat()) }.toFloatArray())
                    }
                    approx.release(); contour.release()
                }
                return best?.takeIf { it.isValid(src.width * src.height * minFraction.toFloat()) }
            } finally {
                gray.release(); blur.release(); edges.release()
                contours.forEach { try { it.release() } catch (_: Throwable) {} }
            }
        } finally { input.release(); work.release() }
    }

    private fun aspectAllowed(aspect: Double, mode: ScanMode): Boolean = when (mode) {
        ScanMode.CARD -> aspect in 1.20..2.20
        ScanMode.DOCUMENT -> aspect in 0.45..2.80
    }

    private fun quadAspect(p: Array<Point>): Double {
        val w1 = dist(p[0], p[1]); val w2 = dist(p[3], p[2])
        val h1 = dist(p[0], p[3]); val h2 = dist(p[1], p[2])
        val w = (w1 + w2) / 2.0; val h = (h1 + h2) / 2.0
        return max(w, h) / max(1.0, minOf(w, h))
    }

    private fun dist(a: Point, b: Point): Double = kotlin.math.hypot(a.x - b.x, a.y - b.y)

    private fun polygonArea(p: Array<Point>): Double {
        var a = 0.0
        for (i in 0 until 4) { val j = (i + 1) % 4; a += p[i].x * p[j].y - p[j].x * p[i].y }
        return abs(a) / 2.0
    }

    private fun orderPoints(points: Array<Point>): Array<Point> {
        val tl = points.minBy { it.x + it.y }
        val br = points.maxBy { it.x + it.y }
        val tr = points.maxBy { it.x - it.y }
        val bl = points.minBy { it.x - it.y }
        return arrayOf(tl, tr, br, bl)
    }
}

private object MatOfByteCompat {
    fun decode(bytes: ByteArray): Mat? {
        if (bytes.isEmpty()) return null
        val mat = MatOfByteCompatMat.from(bytes)
        val decoded = Imgcodecs.imdecode(mat, Imgcodecs.IMREAD_COLOR)
        mat.release()
        return decoded.takeIf { !it.empty() }
    }
}

private object MatOfByteCompatMat {
    fun from(bytes: ByteArray): Mat {
        val mat = Mat(1, bytes.size, org.opencv.core.CvType.CV_8UC1)
        mat.put(0, 0, bytes)
        return mat
    }
}
