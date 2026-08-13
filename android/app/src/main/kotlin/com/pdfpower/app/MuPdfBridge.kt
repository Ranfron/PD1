package com.pdfpower.app

import android.os.Handler
import android.os.Looper
import com.artifex.mupdf.fitz.Document
import com.artifex.mupdf.fitz.PDFDocument
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

/**
 * MuPDF 1.28.x bridge (com.artifex.mupdf:fitz).
 * Provides pageCount, info, merge, split, compress (garbage/clean save).
 * AGPL licensed native library from Artifex.
 */
class MuPdfBridge : MethodChannel.MethodCallHandler {

    private val executor = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "version" -> result.success("1.28.x-fitz")
            "isAvailable" -> result.success(true)
            "pageCount" -> {
                val path = call.argument<String>("path")
                if (path.isNullOrBlank()) {
                    result.error("arg", "path required", null)
                    return
                }
                executor.execute {
                    try {
                        val doc = Document.openDocument(path)
                        val n = doc.countPages()
                        doc.destroy()
                        main.post { result.success(n) }
                    } catch (e: Exception) {
                        main.post { result.error("mupdf", e.message, null) }
                    }
                }
            }
            "info" -> {
                val path = call.argument<String>("path")
                if (path.isNullOrBlank()) {
                    result.error("arg", "path required", null)
                    return
                }
                executor.execute {
                    try {
                        val doc = Document.openDocument(path)
                        val map = HashMap<String, Any?>()
                        map["pageCount"] = doc.countPages()
                        map["needsPassword"] = doc.needsPassword()
                        map["title"] = doc.getMetaData(Document.META_INFO_TITLE) ?: ""
                        map["author"] = doc.getMetaData(Document.META_INFO_AUTHOR) ?: ""
                        map["format"] = doc.getMetaData(Document.META_FORMAT) ?: ""
                        map["encryption"] = doc.getMetaData(Document.META_ENCRYPTION) ?: ""
                        doc.destroy()
                        main.post { result.success(map) }
                    } catch (e: Exception) {
                        main.post { result.error("mupdf", e.message, null) }
                    }
                }
            }
            "merge" -> {
                val paths = call.argument<List<String>>("paths")
                val outPath = call.argument<String>("outPath")
                if (paths == null || paths.size < 2 || outPath.isNullOrBlank()) {
                    result.error("arg", "paths (>=2) and outPath required", null)
                    return
                }
                executor.execute {
                    try {
                        mergePdfs(paths, outPath)
                        main.post { result.success(outPath) }
                    } catch (e: Exception) {
                        main.post { result.error("mupdf", e.message, null) }
                    }
                }
            }
            "split" -> {
                val path = call.argument<String>("path")
                val outPath = call.argument<String>("outPath")
                val start = call.argument<Int>("start") ?: 1
                val end = call.argument<Int>("end") ?: start
                if (path.isNullOrBlank() || outPath.isNullOrBlank()) {
                    result.error("arg", "path and outPath required", null)
                    return
                }
                executor.execute {
                    try {
                        splitPdf(path, outPath, start, end)
                        main.post { result.success(outPath) }
                    } catch (e: Exception) {
                        main.post { result.error("mupdf", e.message, null) }
                    }
                }
            }
            "compress" -> {
                val path = call.argument<String>("path")
                val outPath = call.argument<String>("outPath")
                if (path.isNullOrBlank() || outPath.isNullOrBlank()) {
                    result.error("arg", "path and outPath required", null)
                    return
                }
                executor.execute {
                    try {
                        // garbage collect + clean + compress streams
                        val doc = Document.openDocument(path)
                        val pdf = doc as? PDFDocument
                            ?: throw Exception("Not a PDF document")
                        pdf.save(outPath, "garbage=compact,clean,compress,compress-images,compress-fonts")
                        doc.destroy()
                        main.post { result.success(outPath) }
                    } catch (e: Exception) {
                        main.post { result.error("mupdf", e.message, null) }
                    }
                }
            }
            else -> result.notImplemented()
        }
    }

    private fun mergePdfs(paths: List<String>, outPath: String) {
        val first = Document.openDocument(paths[0])
        val out = first as? PDFDocument
            ?: throw Exception("First file is not a PDF")
        // Graft remaining documents' pages
        for (i in 1 until paths.size) {
            val srcDoc = Document.openDocument(paths[i])
            val src = srcDoc as? PDFDocument
                ?: run {
                    srcDoc.destroy()
                    throw Exception("Not a PDF: ${paths[i]}")
                }
            val n = src.countPages()
            val graft = out.newPDFGraftMap()
            for (p in 0 until n) {
                val pageObj = src.findPage(p)
                val grafted = graft.graftObject(pageObj)
                out.insertPage(-1, grafted)
            }
            graft.destroy()
            srcDoc.destroy()
        }
        out.save(outPath, "compress")
        first.destroy()
    }

    private fun splitPdf(path: String, outPath: String, start1: Int, end1: Int) {
        val srcDoc = Document.openDocument(path)
        val src = srcDoc as? PDFDocument
            ?: throw Exception("Not a PDF")
        val total = src.countPages()
        val start = (start1 - 1).coerceIn(0, total - 1)
        val end = end1.coerceIn(start + 1, total)

        val out = PDFDocument()
        val graft = out.newPDFGraftMap()
        for (p in start until end) {
            val pageObj = src.findPage(p)
            val grafted = graft.graftObject(pageObj)
            out.insertPage(-1, grafted)
        }
        graft.destroy()
        out.save(outPath, "compress")
        out.destroy()
        srcDoc.destroy()
    }
}
