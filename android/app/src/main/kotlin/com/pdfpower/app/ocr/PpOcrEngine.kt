package com.pdfpower.app.ocr

import ai.onnxruntime.OnnxTensor
import ai.onnxruntime.OrtEnvironment
import ai.onnxruntime.OrtSession
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.ColorMatrix
import android.graphics.ColorMatrixColorFilter
import android.graphics.Matrix
import android.graphics.Paint
import android.util.Log
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.nio.FloatBuffer
import kotlin.math.ceil
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt

/**
 * Real PP-OCR pipeline on Android via ONNX Runtime.
 *
 * DET: PP-OCRv6 Medium DET (DB-style heatmap)
 * REC: devanagari_PP-OCRv5_mobile_rec (CTC / sequence)
 *
 * Pre/post-process follows standard PaddleOCR mobile conventions so that
 * official or paddle2onnx-exported models work when placed at the paths
 * passed to [load].
 */
class PpOcrEngine {

    companion object {
        private const val TAG = "PpOcrEngine"
        private const val DET_LIMIT = 960
        private const val DET_THRESH = 0.2f
        private const val BOX_THRESH = 0.45f
        private const val UNCLIP_RATIO = 1.4f
        private const val REC_IMG_H = 48
        private const val REC_MAX_W = 320
    }

    private var env: OrtEnvironment? = null
    private var detSession: OrtSession? = null
    private var recSession: OrtSession? = null
    private var charset: List<String> = emptyList()
    @Volatile private var ready = false

    fun isReady(): Boolean = ready

    fun load(detPath: String, recPath: String, dictPath: String): Boolean {
        unload()
        return try {
            val e = OrtEnvironment.getEnvironment()
            val opts = OrtSession.SessionOptions().apply {
                setIntraOpNumThreads(4)
                setOptimizationLevel(OrtSession.SessionOptions.OptLevel.ALL_OPT)
            }
            require(File(detPath).exists()) { "DET missing: $detPath" }
            require(File(recPath).exists()) { "REC missing: $recPath" }
            require(File(dictPath).exists()) { "Dict missing: $dictPath" }

            detSession = e.createSession(detPath, opts)
            recSession = e.createSession(recPath, opts)
            charset = File(dictPath).readLines()
                .map { it.trimEnd('\r') }
                .filter { it.isNotEmpty() }
                .toMutableList()
                .also { chars -> if (chars.lastOrNull() != " ") chars.add(" ") }
            // PaddleOCR CTCLabelDecode uses class 0 as blank; dictionary characters start at class 1.
            require(charset.isNotEmpty()) { "Recognition dictionary is empty" }
            env = e
            ready = true
            Log.i(TAG, "Loaded DET+REC. charset=${charset.size}")
            true
        } catch (t: Throwable) {
            Log.e(TAG, "load failed", t)
            unload()
            false
        }
    }

    fun unload() {
        ready = false
        try { detSession?.close() } catch (_: Throwable) {}
        try { recSession?.close() } catch (_: Throwable) {}
        detSession = null
        recSession = null
        charset = emptyList()
    }

    /**
     * Full page OCR → JSON:
     * {"page":N,"engine":"pp_ocr","objects":[{"text":"...","bbox":[x0,y0,x1,y1],"confidence":0.9}]}
     * Coordinates are normalized 0–1 relative to image size.
     */
    fun analyzeImage(imagePath: String, page: Int): String {
        if (!ready) {
            return """{"page":$page,"engine":"not_ready","objects":[]}"""
        }
        val bmp = BitmapFactory.decodeFile(imagePath)
            ?: return """{"page":$page,"engine":"decode_error","objects":[]}"""
        return try {
            val boxes = detect(bmp)
            val objects = JSONArray()
            for (box in boxes) {
                val crop = cropQuad(bmp, box.points)
                val (text, conf) = recognize(crop)
                if (text.isBlank()) continue
                val norm = normalizeBox(box.points, bmp.width, bmp.height)
                objects.put(JSONObject().apply {
                    put("text", text)
                    put("confidence", conf.toDouble())
                    put("bbox", JSONArray(listOf(norm[0], norm[1], norm[2], norm[3])))
                    put("type", "text")
                })
            }
            JSONObject().apply {
                put("page", page)
                put("engine", "pp_ocr")
                put("objects", objects)
            }.toString()
        } catch (t: Throwable) {
            Log.e(TAG, "analyze failed", t)
            """{"page":$page,"engine":"error","objects":[],"error":"${t.message}"}"""
        } finally {
            if (!bmp.isRecycled) bmp.recycle()
        }
    }

    fun processPlainText(imagePath: String): String {
        val json = analyzeImage(imagePath, 1)
        return try {
            val arr = JSONObject(json).optJSONArray("objects") ?: return ""
            buildString {
                for (i in 0 until arr.length()) {
                    val t = arr.getJSONObject(i).optString("text")
                    if (t.isNotBlank()) {
                        if (isNotEmpty()) append('\n')
                        append(t)
                    }
                }
            }
        } catch (_: Throwable) {
            ""
        }
    }

    // ── Detection ──────────────────────────────────────────────

    private data class DetBox(val points: FloatArray) // 8 floats: x0,y0 ... x3,y3 in original px

    private fun detect(src: Bitmap): List<DetBox> {
        val session = detSession ?: return emptyList()
        val e = env ?: return emptyList()

        val (scaled, ratio) = resizeLimitSide(src, DET_LIMIT)
        val w = scaled.width
        val h = scaled.height
        // pad to multiple of 32
        val pw = ((w + 31) / 32) * 32
        val ph = ((h + 31) / 32) * 32
        val padded = Bitmap.createBitmap(pw, ph, Bitmap.Config.ARGB_8888)
        Canvas(padded).drawBitmap(scaled, 0f, 0f, null)

        val input = bitmapToNCHW(padded, mean = floatArrayOf(0.485f, 0.456f, 0.406f),
            std = floatArrayOf(0.229f, 0.224f, 0.225f), bgr = true)
        val shape = longArrayOf(1, 3, ph.toLong(), pw.toLong())
        val tensor = OnnxTensor.createTensor(e, FloatBuffer.wrap(input), shape)
        val inputName = session.inputNames.iterator().next()
        val results = session.run(mapOf(inputName to tensor))
        tensor.close()

        val out = results[0].value
        results.close()
        if (!scaled.isRecycled && scaled !== src) scaled.recycle()
        if (!padded.isRecycled) padded.recycle()

        // Expect [1,1,H,W] or [1,H,W] probability map
        val map = flattenDetOutput(out, ph, pw) ?: return emptyList()
        return boxesFromMap(map, ph, pw, ratio, src.width, src.height)
    }

    private fun flattenDetOutput(out: Any, h: Int, w: Int): FloatArray? {
        val flat = FloatArray(h * w)
        var pos = 0
        fun visit(v: Any?) {
            if (pos >= flat.size) return
            when (v) {
                is FloatArray -> {
                    val n = min(v.size, flat.size - pos)
                    v.copyInto(flat, pos, 0, n); pos += n
                }
                is Array<*> -> v.forEach { visit(it) }
            }
        }
        visit(out)
        return if (pos == flat.size) flat else null
    }

    private fun boxesFromMap(
        map: FloatArray,
        mh: Int,
        mw: Int,
        ratio: Float,
        origW: Int,
        origH: Int
    ): List<DetBox> {
        // Simple connected-component style box extraction on thresholded map.
        // Good enough for documents; full DB unclip can be refined later.
        val bin = BooleanArray(mh * mw)
        for (i in map.indices) bin[i] = map[i] >= DET_THRESH

        val visited = BooleanArray(mh * mw)
        val boxes = mutableListOf<DetBox>()
        val qx = IntArray(mh * mw)
        val qy = IntArray(mh * mw)

        for (y in 0 until mh) {
            for (x in 0 until mw) {
                val idx = y * mw + x
                if (!bin[idx] || visited[idx]) continue
                var minX = x
                var maxX = x
                var minY = y
                var maxY = y
                var scoreSum = 0f
                var count = 0
                var qh = 0
                var qt = 0
                qx[qt] = x
                qy[qt] = y
                qt++
                visited[idx] = true
                while (qh < qt) {
                    val cx = qx[qh]
                    val cy = qy[qh]
                    qh++
                    scoreSum += map[cy * mw + cx]
                    count++
                    minX = min(minX, cx)
                    maxX = max(maxX, cx)
                    minY = min(minY, cy)
                    maxY = max(maxY, cy)
                    for (dy in -1..1) for (dx in -1..1) {
                        if (dx == 0 && dy == 0) continue
                        val nx = cx + dx
                        val ny = cy + dy
                        if (nx < 0 || ny < 0 || nx >= mw || ny >= mh) continue
                        val nidx = ny * mw + nx
                        if (visited[nidx] || !bin[nidx]) continue
                        visited[nidx] = true
                        qx[qt] = nx
                        qy[qt] = ny
                        qt++
                    }
                }
                if (count < 16) continue
                val meanScore = scoreSum / count
                if (meanScore < BOX_THRESH) continue

                // expand by unclip ratio approx
                val bw = maxX - minX + 1
                val bh = maxY - minY + 1
                val padX = ((bw * (UNCLIP_RATIO - 1f)) / 2f).roundToInt()
                val padY = ((bh * (UNCLIP_RATIO - 1f)) / 2f).roundToInt()
                minX = max(0, minX - padX)
                minY = max(0, minY - padY)
                maxX = min(mw - 1, maxX + padX)
                maxY = min(mh - 1, maxY + padY)

                // map back to original image coords
                val x0 = (minX / ratio).coerceIn(0f, origW - 1f)
                val y0 = (minY / ratio).coerceIn(0f, origH - 1f)
                val x1 = (maxX / ratio).coerceIn(0f, origW - 1f)
                val y1 = (maxY / ratio).coerceIn(0f, origH - 1f)
                if (x1 - x0 < 4 || y1 - y0 < 4) continue
                boxes.add(
                    DetBox(
                        floatArrayOf(
                            x0, y0, x1, y0,
                            x1, y1, x0, y1
                        )
                    )
                )
            }
        }
        // sort top-to-bottom, left-to-right
        return boxes.sortedWith(compareBy({ it.points[1] }, { it.points[0] }))
    }

    // ── Recognition ────────────────────────────────────────────

    private fun recognize(crop: Bitmap): Pair<String, Float> {
        val session = recSession ?: return "" to 0f
        val e = env ?: return "" to 0f
        if (crop.width < 2 || crop.height < 2) return "" to 0f

        val resized = resizeRec(crop)
        val input = bitmapToNCHW(
            resized,
            mean = floatArrayOf(0.5f, 0.5f, 0.5f),
            std = floatArrayOf(0.5f, 0.5f, 0.5f),
            bgr = true
        )
        val shape = longArrayOf(1, 3, REC_IMG_H.toLong(), resized.width.toLong())
        val tensor = OnnxTensor.createTensor(e, FloatBuffer.wrap(input), shape)
        val inputName = session.inputNames.iterator().next()
        val results = session.run(mapOf(inputName to tensor))
        tensor.close()
        val out = results[0].value
        Log.d(TAG, "REC output=${describeTensor(out)} input=${resized.width}x${resized.height}")
        results.close()
        if (!resized.isRecycled && resized !== crop) resized.recycle()

        return ctcDecode(out)
    }

    private fun describeTensor(v: Any?): String = when (v) {
        is Array<*> -> {
            val a = v.getOrNull(0)
            if (a is Array<*>) "Array[${v.size},${a.size},${(a.getOrNull(0) as? FloatArray)?.size ?: 0}]"
            else "Array[${v.size}]"
        }
        else -> v?.javaClass?.simpleName ?: "null"
    }

    private fun ctcDecode(out: Any): Pair<String, Float> {
        return try {
            // PP-OCRv5 mobile REC uses CTC output. Depending on the ONNX exporter,
            // the tensor can be [1,T,C] or [1,C,T]. Detect the orientation from
            // the dictionary class count instead of using an arbitrary size cutoff.
            val raw = when (out) {
                is Array<*> -> out.getOrNull(0)
                else -> null
            }

            if (raw !is Array<*>) return "" to 0f

            @Suppress("UNCHECKED_CAST")
            val matrix = raw as Array<FloatArray>
            if (matrix.isEmpty()) return "" to 0f

            val classCount = charset.size + 1 // dictionary + CTC blank
            val rows = matrix.size
            val cols = matrix[0].size

            val steps: Array<FloatArray> = when {
                cols == classCount -> matrix                 // [T,C]
                rows == classCount -> Array(cols) { t ->
                    FloatArray(rows) { c -> matrix[c][t] }   // [C,T] -> [T,C]
                }
                else -> {
                    // Some exporters expose an equivalent tensor with a small
                    // class-count discrepancy. Prefer the dimension closest to
                    // the expected CTC class count.
                    if (kotlin.math.abs(cols - classCount) <= kotlin.math.abs(rows - classCount)) {
                        matrix
                    } else {
                        Array(cols) { t -> FloatArray(rows) { c -> matrix[c][t] } }
                    }
                }
            }

            decodeSteps(steps)
        } catch (t: Throwable) {
            Log.e(TAG, "ctc", t)
            "" to 0f
        }
    }

    private fun decodeSteps(steps: Array<FloatArray>): Pair<String, Float> {
        // PaddleOCR CTCLabelDecode reserves class 0 for CTC blank.
        // Dictionary character N is model class N+1.
        // Using the blank as the last class shifts every character by one.
        val blank = 0
        val sb = StringBuilder()
        var last = blank
        var confSum = 0f
        var confN = 0

        for (row in steps) {
            if (row.isEmpty()) continue

            var maxI = 0
            var maxV = row[0]
            for (c in 1 until row.size) {
                if (row[c] > maxV) {
                    maxV = row[c]
                    maxI = c
                }
            }

            // CTC: remove blank and consecutive duplicate labels.
            if (maxI != blank && maxI != last) {
                val dictIndex = maxI - 1
                if (dictIndex >= 0 && dictIndex < charset.size) {
                    sb.append(charset[dictIndex])
                    confSum += maxV
                    confN++
                }
            }
            last = maxI
        }

        return sb.toString() to if (confN > 0) confSum / confN else 0f
    }

    // ── Image helpers ──────────────────────────────────────────

    private fun resizeLimitSide(src: Bitmap, limit: Int): Pair<Bitmap, Float> {
        val maxSide = max(src.width, src.height)
        if (maxSide <= limit) return src to 1f
        val ratio = limit.toFloat() / maxSide
        val nw = max(1, (src.width * ratio).roundToInt())
        val nh = max(1, (src.height * ratio).roundToInt())
        return Bitmap.createScaledBitmap(src, nw, nh, true) to ratio
    }

    private fun resizeRec(src: Bitmap): Bitmap {
        // Official devanagari_PP-OCRv5_mobile_rec inference shape is [3, 48, 320].
        // Keep the text aspect ratio, then right-pad with white pixels.
        val h = REC_IMG_H
        val scale = h.toFloat() / src.height.coerceAtLeast(1)
        val resizedW = (src.width * scale).roundToInt().coerceAtLeast(1)
        val contentW = min(REC_MAX_W, resizedW)

        val scaled = Bitmap.createScaledBitmap(src, contentW, h, true)
        val out = Bitmap.createBitmap(REC_MAX_W, h, Bitmap.Config.ARGB_8888)
        out.eraseColor(android.graphics.Color.WHITE)
        Canvas(out).drawBitmap(scaled, 0f, 0f, null)
        if (scaled !== src && !scaled.isRecycled) scaled.recycle()
        return out
    }

    private fun cropQuad(src: Bitmap, pts: FloatArray): Bitmap {
        return com.pdfpower.app.scanner.PerspectiveCorrector.correct(
            src, com.pdfpower.app.scanner.Quad(pts), enhance = false
        )
    }

    private fun normalizeBox(pts: FloatArray, w: Int, h: Int): FloatArray {
        val minX = min(min(pts[0], pts[2]), min(pts[4], pts[6])) / w
        val maxX = max(max(pts[0], pts[2]), max(pts[4], pts[6])) / w
        val minY = min(min(pts[1], pts[3]), min(pts[5], pts[7])) / h
        val maxY = max(max(pts[1], pts[3]), max(pts[5], pts[7])) / h
        return floatArrayOf(
            minX.coerceIn(0f, 1f),
            minY.coerceIn(0f, 1f),
            maxX.coerceIn(0f, 1f),
            maxY.coerceIn(0f, 1f)
        )
    }

    private fun bitmapToNCHW(
        bmp: Bitmap,
        mean: FloatArray,
        std: FloatArray,
        bgr: Boolean = false
    ): FloatArray {
        val w = bmp.width
        val h = bmp.height
        val pixels = IntArray(w * h)
        bmp.getPixels(pixels, 0, w, 0, 0, w, h)
        val out = FloatArray(3 * w * h)
        val area = w * h
        for (i in pixels.indices) {
            val p = pixels[i]
            val r = ((p shr 16) and 0xFF) / 255f
            val g = ((p shr 8) and 0xFF) / 255f
            val b = (p and 0xFF) / 255f
            val c0 = if (bgr) b else r
            val c2 = if (bgr) r else b
            out[i] = (c0 - mean[0]) / std[0]
            out[area + i] = (g - mean[1]) / std[1]
            out[2 * area + i] = (c2 - mean[2]) / std[2]
        }
        return out
    }
}
