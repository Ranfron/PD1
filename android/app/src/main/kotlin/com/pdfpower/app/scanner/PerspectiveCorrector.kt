package com.pdfpower.app.scanner

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.ColorMatrix
import android.graphics.ColorMatrixColorFilter
import android.graphics.Paint
import org.opencv.core.Mat
import org.opencv.core.MatOfPoint2f
import org.opencv.core.Point
import org.opencv.core.Size
import org.opencv.imgcodecs.Imgcodecs
import org.opencv.imgproc.Imgproc
import java.io.ByteArrayOutputStream
import kotlin.math.hypot
import kotlin.math.max
import kotlin.math.roundToInt

object PerspectiveCorrector {
    /** True four-point perspective correction using OpenCV homography. */
    fun correct(src: Bitmap, quad: Quad, enhance: Boolean = true): Bitmap {
        if (!OpenCvSupport.ensureLoaded()) return fallbackCrop(src, quad, enhance)
        val bytes = ByteArrayOutputStream().use { out ->
            src.compress(Bitmap.CompressFormat.JPEG, 95, out)
            out.toByteArray()
        }
        val input = Mat(1, bytes.size, org.opencv.core.CvType.CV_8UC1)
        input.put(0, 0, bytes)
        val mat = Imgcodecs.imdecode(input, Imgcodecs.IMREAD_COLOR)
        input.release()
        if (mat.empty()) return fallbackCrop(src, quad, enhance)
        try {
            val p = quad.points
            val tl = Point(p[0].toDouble(), p[1].toDouble())
            val tr = Point(p[2].toDouble(), p[3].toDouble())
            val br = Point(p[4].toDouble(), p[5].toDouble())
            val bl = Point(p[6].toDouble(), p[7].toDouble())
            val width = max(hypot(tr.x - tl.x, tr.y - tl.y), hypot(br.x - bl.x, br.y - bl.y)).roundToInt().coerceAtLeast(32)
            val height = max(hypot(bl.x - tl.x, bl.y - tl.y), hypot(br.x - tr.x, br.y - tr.y)).roundToInt().coerceAtLeast(32)
            val maxOut = 2200
            val scale = minOf(1.0, maxOut.toDouble() / max(width, height))
            val outW = (width * scale).roundToInt().coerceAtLeast(32)
            val outH = (height * scale).roundToInt().coerceAtLeast(32)
            val srcPts = MatOfPoint2f(tl, tr, br, bl)
            val dstPts = MatOfPoint2f(
                Point(0.0, 0.0), Point((outW - 1).toDouble(), 0.0),
                Point((outW - 1).toDouble(), (outH - 1).toDouble()), Point(0.0, (outH - 1).toDouble())
            )
            val transform = Imgproc.getPerspectiveTransform(srcPts, dstPts)
            val warped = Mat()
            Imgproc.warpPerspective(mat, warped, transform, Size(outW.toDouble(), outH.toDouble()), Imgproc.INTER_CUBIC)
            val encoded = Mat()
            Imgcodecs.imencode(".jpg", warped, encoded, org.opencv.core.MatOfInt(Imgcodecs.IMWRITE_JPEG_QUALITY, 95))
            val data = ByteArray(encoded.total().toInt())
            encoded.get(0, 0, data)
            val bitmap = BitmapFactory.decodeByteArray(data, 0, data.size)
            srcPts.release(); dstPts.release(); transform.release(); warped.release(); encoded.release(); mat.release()
            return if (bitmap != null && enhance) enhanceDocument(bitmap) else bitmap ?: fallbackCrop(src, quad, enhance)
        } catch (_: Throwable) {
            mat.release()
            return fallbackCrop(src, quad, enhance)
        }
    }

    private fun fallbackCrop(src: Bitmap, quad: Quad, enhance: Boolean): Bitmap {
        val p = quad.points
        val minX = minOf(p[0], p[2], p[4], p[6]).toInt().coerceAtLeast(0)
        val maxX = maxOf(p[0], p[2], p[4], p[6]).toInt().coerceAtMost(src.width)
        val minY = minOf(p[1], p[3], p[5], p[7]).toInt().coerceAtLeast(0)
        val maxY = maxOf(p[1], p[3], p[5], p[7]).toInt().coerceAtMost(src.height)
        val crop = Bitmap.createBitmap(src, minX, minY, (maxX - minX).coerceAtLeast(1), (maxY - minY).coerceAtLeast(1))
        return if (enhance) enhanceDocument(crop) else crop
    }

    fun enhanceDocument(src: Bitmap): Bitmap {
        val cm = ColorMatrix(floatArrayOf(
            1.18f, 0f, 0f, 0f, -12f,
            0f, 1.18f, 0f, 0f, -12f,
            0f, 0f, 1.18f, 0f, -12f,
            0f, 0f, 0f, 1f, 0f
        ))
        val out = Bitmap.createBitmap(src.width, src.height, Bitmap.Config.ARGB_8888)
        Canvas(out).drawBitmap(src, 0f, 0f, Paint(Paint.FILTER_BITMAP_FLAG).apply {
            colorFilter = ColorMatrixColorFilter(cm)
        })
        if (out !== src && !src.isRecycled) src.recycle()
        return out
    }

    fun toGrayscale(src: Bitmap): Bitmap {
        val cm = ColorMatrix().apply { setSaturation(0f) }
        val out = Bitmap.createBitmap(src.width, src.height, Bitmap.Config.ARGB_8888)
        Canvas(out).drawBitmap(src, 0f, 0f, Paint().apply { colorFilter = ColorMatrixColorFilter(cm) })
        return out
    }

    fun toBlackWhite(src: Bitmap, threshold: Int = 140): Bitmap {
        val gray = toGrayscale(src)
        val w = gray.width; val h = gray.height
        val px = IntArray(w * h)
        gray.getPixels(px, 0, w, 0, 0, w, h)
        for (i in px.indices) {
            val v = Color.red(px[i])
            px[i] = if (v > threshold) Color.WHITE else Color.BLACK
        }
        val out = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
        out.setPixels(px, 0, w, 0, 0, w, h)
        if (!gray.isRecycled) gray.recycle()
        return out
    }
}
