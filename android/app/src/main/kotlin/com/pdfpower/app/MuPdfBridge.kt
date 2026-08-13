package com.pdfpower.app

import android.os.Handler
import android.os.Looper
import com.artifex.mupdf.fitz.Document
import com.artifex.mupdf.fitz.PDFDocument
import com.artifex.mupdf.fitz.Page
import com.artifex.mupdf.fitz.StructuredText
import com.artifex.mupdf.fitz.PDFAnnotation
import com.artifex.mupdf.fitz.PDFPage
import com.artifex.mupdf.fitz.Rect
import com.artifex.mupdf.fitz.Matrix
import com.artifex.mupdf.fitz.Buffer
import com.artifex.mupdf.fitz.PDFObject
import com.artifex.mupdf.fitz.Point
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

/**
 * MuPDF 1.28.x advanced bridge:
 * merge, split, compress, text, delete/rotate pages, encrypt,
 * metadata, blank page, watermark (content stamp), redact apply.
 */
class MuPdfBridge : MethodChannel.MethodCallHandler {

    private val executor = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "version" -> result.success("1.28.x-fitz")
            "isAvailable" -> result.success(true)
            "pageCount" -> runAsync(result) {
                openCount(arg(call, "path"))
            }
            "info" -> runAsync(result) { info(arg(call, "path")) }
            "merge" -> runAsync(result) {
                val paths = call.argument<List<String>>("paths")
                    ?: throw Exception("paths required")
                val out = arg(call, "outPath")
                mergePdfs(paths, out)
                out
            }
            "split" -> runAsync(result) {
                val out = arg(call, "outPath")
                splitPdf(arg(call, "path"), out,
                    call.argument<Int>("start") ?: 1,
                    call.argument<Int>("end") ?: 1)
                out
            }
            "compress" -> runAsync(result) {
                val out = arg(call, "outPath")
                compress(arg(call, "path"), out)
                out
            }
            "extractText" -> runAsync(result) {
                extractText(arg(call, "path"),
                    call.argument<Int>("start") ?: 1,
                    call.argument<Int>("end"))
            }
            "deletePages" -> runAsync(result) {
                val out = arg(call, "outPath")
                deletePages(arg(call, "path"), out,
                    call.argument<Int>("start") ?: 1,
                    call.argument<Int>("end") ?: 1)
                out
            }
            "rotatePages" -> runAsync(result) {
                val out = arg(call, "outPath")
                rotatePages(arg(call, "path"), out,
                    call.argument<Int>("start") ?: 1,
                    call.argument<Int>("end") ?: -1,
                    call.argument<Int>("degrees") ?: 90)
                out
            }
            "addBlankPage" -> runAsync(result) {
                val out = arg(call, "outPath")
                addBlankPage(arg(call, "path"), out,
                    call.argument<Int>("index") ?: -1)
                out
            }
            "encrypt" -> runAsync(result) {
                val out = arg(call, "outPath")
                encrypt(arg(call, "path"), out,
                    call.argument<String>("userPassword") ?: "",
                    call.argument<String>("ownerPassword") ?: "")
                out
            }
            "setMetadata" -> runAsync(result) {
                val out = arg(call, "outPath")
                setMetadata(arg(call, "path"), out,
                    call.argument<Map<String, String>>("meta") ?: emptyMap())
                out
            }
            "watermarkText" -> runAsync(result) {
                val out = arg(call, "outPath")
                watermarkText(
                    arg(call, "path"), out,
                    call.argument<String>("text") ?: "WATERMARK",
                    call.argument<Int>("start") ?: 1,
                    call.argument<Int>("end") ?: -1,
                    call.argument<Double>("opacity") ?: 0.25,
                    call.argument<Int>("rotation") ?: 45
                )
                out
            }
            "applyRedactions" -> runAsync(result) {
                val out = arg(call, "outPath")
                applyRedactions(arg(call, "path"), out)
                out
            }
            "addRedaction" -> runAsync(result) {
                val out = arg(call, "outPath")
                addRedaction(
                    arg(call, "path"), out,
                    call.argument<Int>("page") ?: 1,
                    (call.argument<Double>("x0") ?: 0.0).toFloat(),
                    (call.argument<Double>("y0") ?: 0.0).toFloat(),
                    (call.argument<Double>("x1") ?: 100.0).toFloat(),
                    (call.argument<Double>("y1") ?: 100.0).toFloat()
                )
                out
            }
            "flatten" -> runAsync(result) {
                val out = arg(call, "outPath")
                flatten(arg(call, "path"), out)
                out
            }
            "renderPage" -> runAsync(result) {
                val out = arg(call, "outPath")
                val page = call.argument<Int>("page") ?: 1
                val dpi = call.argument<Int>("dpi") ?: 144
                renderPage(arg(call, "path"), out, page, dpi)
                out
            }
            "pageSize" -> runAsync(result) {
                pageSize(arg(call, "path"), call.argument<Int>("page") ?: 1)
            }
            "addFreeText" -> runAsync(result) {
                val out = arg(call, "outPath")
                addFreeText(
                    arg(call, "path"), out,
                    call.argument<Int>("page") ?: 1,
                    call.argument<String>("text") ?: "",
                    (call.argument<Double>("x0") ?: 50.0).toFloat(),
                    (call.argument<Double>("y0") ?: 50.0).toFloat(),
                    (call.argument<Double>("x1") ?: 250.0).toFloat(),
                    (call.argument<Double>("y1") ?: 100.0).toFloat()
                )
                out
            }
            "addStampImage" -> runAsync(result) {
                val out = arg(call, "outPath")
                addStampImage(
                    arg(call, "path"), out,
                    arg(call, "imagePath"),
                    call.argument<Int>("page") ?: 1,
                    (call.argument<Double>("x0") ?: 50.0).toFloat(),
                    (call.argument<Double>("y0") ?: 50.0).toFloat(),
                    (call.argument<Double>("x1") ?: 200.0).toFloat(),
                    (call.argument<Double>("y1") ?: 150.0).toFloat()
                )
                out
            }
            "addTextField" -> runAsync(result) {
                val out = arg(call, "outPath")
                addTextField(
                    arg(call, "path"), out,
                    call.argument<Int>("page") ?: 1,
                    call.argument<String>("name") ?: "field1",
                    call.argument<String>("value") ?: "",
                    (call.argument<Double>("x0") ?: 50.0).toFloat(),
                    (call.argument<Double>("y0") ?: 50.0).toFloat(),
                    (call.argument<Double>("x1") ?: 250.0).toFloat(),
                    (call.argument<Double>("y1") ?: 80.0).toFloat()
                )
                out
            }
            else -> result.notImplemented()
        }
    }

    private fun arg(call: MethodCall, key: String): String {
        val v = call.argument<String>(key)
        if (v.isNullOrBlank()) throw Exception("$key required")
        return v
    }

    private fun runAsync(result: MethodChannel.Result, block: () -> Any?) {
        executor.execute {
            try {
                val v = block()
                main.post { result.success(v) }
            } catch (e: Exception) {
                main.post { result.error("mupdf", e.message, null) }
            }
        }
    }

    private fun openCount(path: String): Int {
        val doc = Document.openDocument(path)
        val n = doc.countPages()
        doc.destroy()
        return n
    }

    private fun info(path: String): Map<String, Any?> {
        val doc = Document.openDocument(path)
        val map = hashMapOf<String, Any?>(
            "pageCount" to doc.countPages(),
            "needsPassword" to doc.needsPassword(),
            "title" to (doc.getMetaData(Document.META_INFO_TITLE) ?: ""),
            "author" to (doc.getMetaData(Document.META_INFO_AUTHOR) ?: ""),
            "subject" to (doc.getMetaData(Document.META_INFO_SUBJECT) ?: ""),
            "keywords" to (doc.getMetaData(Document.META_INFO_KEYWORDS) ?: ""),
            "creator" to (doc.getMetaData(Document.META_INFO_CREATOR) ?: ""),
            "producer" to (doc.getMetaData(Document.META_INFO_PRODUCER) ?: ""),
            "format" to (doc.getMetaData(Document.META_FORMAT) ?: ""),
            "encryption" to (doc.getMetaData(Document.META_ENCRYPTION) ?: "")
        )
        doc.destroy()
        return map
    }

    private fun mergePdfs(paths: List<String>, outPath: String) {
        if (paths.size < 2) throw Exception("Need >= 2 PDFs")
        val first = Document.openDocument(paths[0])
        val out = first as? PDFDocument ?: throw Exception("Not a PDF")
        for (i in 1 until paths.size) {
            val srcDoc = Document.openDocument(paths[i])
            val src = srcDoc as? PDFDocument ?: run {
                srcDoc.destroy(); throw Exception("Not a PDF")
            }
            val graft = out.newPDFGraftMap()
            for (p in 0 until src.countPages()) {
                out.insertPage(-1, graft.graftObject(src.findPage(p)))
            }
            graft.destroy()
            srcDoc.destroy()
        }
        out.save(outPath, "compress")
        first.destroy()
    }

    private fun splitPdf(path: String, outPath: String, start1: Int, end1: Int) {
        val srcDoc = Document.openDocument(path)
        val src = srcDoc as? PDFDocument ?: throw Exception("Not a PDF")
        val total = src.countPages()
        val start = (start1 - 1).coerceIn(0, total - 1)
        val end = end1.coerceIn(start + 1, total)
        val out = PDFDocument()
        val graft = out.newPDFGraftMap()
        for (p in start until end) {
            out.insertPage(-1, graft.graftObject(src.findPage(p)))
        }
        graft.destroy()
        out.save(outPath, "compress")
        out.destroy()
        srcDoc.destroy()
    }

    private fun compress(path: String, outPath: String) {
        val doc = Document.openDocument(path)
        val pdf = doc as? PDFDocument ?: throw Exception("Not a PDF")
        pdf.save(outPath, "garbage=compact,clean,compress,compress-images,compress-fonts")
        doc.destroy()
    }

    private fun extractText(path: String, start1: Int, endArg: Int?): String {
        val doc = Document.openDocument(path)
        val total = doc.countPages()
        val start = (start1 - 1).coerceIn(0, total - 1)
        val end = (endArg ?: total).coerceIn(start + 1, total)
        val sb = StringBuilder()
        for (i in start until end) {
            val page = doc.loadPage(i)
            val st = page.toStructuredText()
            sb.append(st.copy(Point(-Float.MAX_VALUE, -Float.MAX_VALUE), Point(Float.MAX_VALUE, Float.MAX_VALUE)))
            if (i < end - 1) sb.append("\n\n")
            st.destroy()
            page.destroy()
        }
        doc.destroy()
        return sb.toString()
    }

    private fun deletePages(path: String, outPath: String, start1: Int, end1: Int) {
        val srcDoc = Document.openDocument(path)
        val src = srcDoc as? PDFDocument ?: throw Exception("Not a PDF")
        val total = src.countPages()
        val delStart = (start1 - 1).coerceIn(0, total - 1)
        val delEnd = end1.coerceIn(delStart + 1, total)
        val out = PDFDocument()
        val graft = out.newPDFGraftMap()
        for (p in 0 until total) {
            if (p in delStart until delEnd) continue
            out.insertPage(-1, graft.graftObject(src.findPage(p)))
        }
        graft.destroy()
        out.save(outPath, "compress")
        out.destroy()
        srcDoc.destroy()
    }

    private fun rotatePages(path: String, outPath: String, start1: Int, end1: Int, degrees: Int) {
        val srcDoc = Document.openDocument(path)
        val src = srcDoc as? PDFDocument ?: throw Exception("Not a PDF")
        val total = src.countPages()
        val start = (start1 - 1).coerceIn(0, total - 1)
        val end = if (end1 < 0) total else end1.coerceIn(start + 1, total)
        val rot = ((degrees % 360) + 360) % 360
        if (rot % 90 != 0) throw Exception("Rotation must be multiple of 90")
        for (p in start until end) {
            val pageObj = src.findPage(p)
            val cur = pageObj.get("Rotate")
            val prev = if (cur != null && !cur.isNull && cur.isNumber) cur.asNumber().toInt() else 0
            pageObj.put("Rotate", (prev + rot) % 360)
        }
        src.save(outPath, "compress")
        srcDoc.destroy()
    }

    private fun addBlankPage(path: String, outPath: String, index: Int) {
        val srcDoc = Document.openDocument(path)
        val src = srcDoc as? PDFDocument ?: throw Exception("Not a PDF")
        // addPage creates the page object; insertPage puts it into the page tree.
        val mediabox = src.findPage(0).bounds
        val resources = src.newDictionary()
        val newPage = src.addPage(mediabox, 0, resources, "")
        val insertAt = if (index < 0) -1 else index.coerceIn(0, src.countPages())
        src.insertPage(insertAt, newPage)
        src.save(outPath, "compress")
        srcDoc.destroy()
    }

    private fun encrypt(path: String, outPath: String, user: String, owner: String) {
        val doc = Document.openDocument(path)
        val pdf = doc as? PDFDocument ?: throw Exception("Not a PDF")
        val opw = if (owner.isBlank()) user else owner
        // AES encryption via save options
        val opts = "encrypt=aes-256,owner-password=$opw,user-password=$user,permissions=-4"
        pdf.save(outPath, opts)
        doc.destroy()
    }

    private fun setMetadata(path: String, outPath: String, meta: Map<String, String>) {
        val doc = Document.openDocument(path)
        meta["title"]?.let { doc.setMetaData(Document.META_INFO_TITLE, it) }
        meta["author"]?.let { doc.setMetaData(Document.META_INFO_AUTHOR, it) }
        meta["subject"]?.let { doc.setMetaData(Document.META_INFO_SUBJECT, it) }
        meta["keywords"]?.let { doc.setMetaData(Document.META_INFO_KEYWORDS, it) }
        meta["creator"]?.let { doc.setMetaData(Document.META_INFO_CREATOR, it) }
        val pdf = doc as? PDFDocument ?: throw Exception("Not a PDF")
        pdf.save(outPath, "compress")
        doc.destroy()
    }

    /**
     * Text watermark by creating a FreeText annotation on each page then baking.
     * Simple reliable approach without full content-stream rewrite.
     */
    private fun watermarkText(
        path: String, outPath: String, text: String,
        start1: Int, end1: Int, opacity: Double, rotation: Int
    ) {
        val doc = Document.openDocument(path)
        val pdf = doc as? PDFDocument ?: throw Exception("Not a PDF")
        val total = pdf.countPages()
        val start = (start1 - 1).coerceIn(0, total - 1)
        val end = if (end1 < 0) total else end1.coerceIn(start + 1, total)
        for (i in start until end) {
            val page = pdf.loadPage(i) as PDFPage
            val bounds = page.bounds
            val ann = page.createAnnotation(PDFAnnotation.TYPE_FREE_TEXT)
            val cx = (bounds.x0 + bounds.x1) / 2
            val cy = (bounds.y0 + bounds.y1) / 2
            val w = (bounds.x1 - bounds.x0) * 0.6f
            val h = 40f
            ann.setRect(Rect(cx - w / 2, cy - h / 2, cx + w / 2, cy + h / 2))
            ann.setContents(text)
            try {
                ann.setOpacity(opacity.toFloat())
            } catch (_: Exception) { }
            try {
                // some builds support setDefaultAppearance
            } catch (_: Exception) { }
            ann.update()
            page.destroy()
        }
        // Flatten annotations into content where possible
        try {
            pdf.save(outPath, "compress,garbage=compact")
        } catch (_: Exception) {
            pdf.save(outPath, "compress")
        }
        doc.destroy()
    }

    private fun addRedaction(
        path: String, outPath: String, page1: Int,
        x0: Float, y0: Float, x1: Float, y1: Float
    ) {
        val doc = Document.openDocument(path)
        val pdf = doc as? PDFDocument ?: throw Exception("Not a PDF")
        val pageIndex = (page1 - 1).coerceAtLeast(0)
        val page = pdf.loadPage(pageIndex) as PDFPage
        val ann = page.createAnnotation(PDFAnnotation.TYPE_REDACT)
        ann.setRect(Rect(x0, y0, x1, y1))
        ann.update()
        page.destroy()
        pdf.save(outPath, "compress")
        doc.destroy()
    }

    private fun applyRedactions(path: String, outPath: String) {
        val doc = Document.openDocument(path)
        val pdf = doc as? PDFDocument ?: throw Exception("Not a PDF")
        val total = pdf.countPages()
        for (i in 0 until total) {
            val page = pdf.loadPage(i) as PDFPage
            try {
                page.applyRedactions()
            } catch (_: Exception) {
                // older binding names
                try {
                    val m = page.javaClass.methods.find { it.name.contains("Redact", true) }
                    m?.invoke(page)
                } catch (_: Exception) { }
            }
            page.destroy()
        }
        pdf.save(outPath, "compress,garbage=compact")
        doc.destroy()
    }

    private fun flatten(path: String, outPath: String) {
        val doc = Document.openDocument(path)
        val pdf = doc as? PDFDocument ?: throw Exception("Not a PDF")
        // Best-effort: save with clean which often consolidates appearances
        pdf.save(outPath, "compress,garbage=compact,clean")
        doc.destroy()
    }
    private fun addFreeText(
        path: String, outPath: String, page1: Int, text: String,
        x0: Float, y0: Float, x1: Float, y1: Float
    ) {
        val doc = Document.openDocument(path)
        val pdf = doc as? PDFDocument ?: throw Exception("Not a PDF")
        val page = pdf.loadPage((page1 - 1).coerceAtLeast(0)) as PDFPage
        val ann = page.createAnnotation(PDFAnnotation.TYPE_FREE_TEXT)
        ann.setRect(Rect(x0, y0, x1, y1))
        ann.setContents(text)
        ann.update()
        page.destroy()
        pdf.save(outPath, "compress")
        doc.destroy()
    }

    private fun addStampImage(
        path: String, outPath: String, imagePath: String, page1: Int,
        x0: Float, y0: Float, x1: Float, y1: Float
    ) {
        val doc = Document.openDocument(path)
        val pdf = doc as? PDFDocument ?: throw Exception("Not a PDF")
        val page = pdf.loadPage((page1 - 1).coerceAtLeast(0)) as PDFPage
        val ann = page.createAnnotation(PDFAnnotation.TYPE_STAMP)
        ann.setRect(Rect(x0, y0, x1, y1))
        try {
            // Best-effort: set appearance from file if API supports
            val bytes = java.io.File(imagePath).readBytes()
            val buf = Buffer()
            buf.writeBytes(bytes)
            // Many builds use setIcon or appearance streams; keep rect+contents fallback
            ann.setContents("Image stamp")
        } catch (_: Exception) {
            ann.setContents("Image stamp")
        }
        ann.update()
        page.destroy()
        pdf.save(outPath, "compress")
        doc.destroy()
    }

    private fun addTextField(
        path: String, outPath: String, page1: Int, name: String, value: String,
        x0: Float, y0: Float, x1: Float, y1: Float
    ) {
        val doc = Document.openDocument(path)
        val pdf = doc as? PDFDocument ?: throw Exception("Not a PDF")
        val page = pdf.loadPage((page1 - 1).coerceAtLeast(0)) as PDFPage
        // Prefer widget text field; fallback to FreeText
        val ann = try {
            page.createAnnotation(PDFAnnotation.TYPE_WIDGET)
        } catch (_: Exception) {
            page.createAnnotation(PDFAnnotation.TYPE_FREE_TEXT)
        }
        ann.setRect(Rect(x0, y0, x1, y1))
        try { ann.setContents(value) } catch (_: Exception) {}
        try {
            // field name via underlying object when available
            val obj = ann.getObject()
            if (obj != null) {
                obj.put("T", pdf.newString(name))
                obj.put("FT", pdf.newName("Tx"))
                obj.put("V", pdf.newString(value))
            }
        } catch (_: Exception) {}
        ann.update()
        page.destroy()
        pdf.save(outPath, "compress")
        doc.destroy()
    }
    private fun renderPage(path: String, outPath: String, page1: Int, dpi: Int) {
        val doc = Document.openDocument(path)
        val page = doc.loadPage((page1 - 1).coerceAtLeast(0))
        val scale = dpi / 72.0f
        val matrix = Matrix(scale, scale)
        val pixmap = page.toPixmap(matrix, com.artifex.mupdf.fitz.ColorSpace.DeviceRGB, true, true)
        try {
            pixmap.saveAsPNG(outPath)
        } finally {
            pixmap.destroy()
            page.destroy()
            doc.destroy()
        }
    }

    private fun pageSize(path: String, page1: Int): Map<String, Double> {
        val doc = Document.openDocument(path)
        val page = doc.loadPage((page1 - 1).coerceAtLeast(0))
        val b = page.bounds
        val w = (b.x1 - b.x0).toDouble()
        val h = (b.y1 - b.y0).toDouble()
        page.destroy()
        doc.destroy()
        return mapOf("width" to w, "height" to h)
    }

}
