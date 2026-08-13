import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'pp_ocr_model_manager.dart';
import 'pdf_edit_engine.dart';
import 'mupdf_service.dart';

/// Flutter ↔ native bridge for PP-OCR pipeline:
///   PP-OCRv6 Medium DET  →  text boxes
///   devanagari_PP-OCRv5_mobile_rec  →  Hindi + English + numbers
class PpOcr {
  static const _channel = MethodChannel('com.pdfpower.app/pp_ocr');
  static bool _initialized = false;

  static Future<bool> isAvailable() async {
    final paths = await PpOcrModelManager.activePaths();
    if (paths == null) return false;
    try {
      var ok = await _channel.invokeMethod<bool>('isReady') ?? false;
      if (!ok) {
        ok = await initialize();
      }
      return ok;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> nativeLibReady() async {
    try {
      return await _channel.invokeMethod<bool>('nativeReady') ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> initialize() async {
    final paths = await PpOcrModelManager.activePaths();
    if (paths == null) return false;
    try {
      final ok = await _channel.invokeMethod<bool>('initialize', {
        'detPath': paths.det,
        'recPath': paths.rec,
        'dictPath': paths.dict,
      });
      _initialized = ok == true;
      return _initialized;
    } catch (_) {
      _initialized = false;
      return false;
    }
  }

  /// Plain text OCR for a single image file.
  static Future<String> processImage(File image) async {
    if (!_initialized) {
      final ok = await initialize();
      if (!ok) return '';
    }
    try {
      return await _channel.invokeMethod<String>('processImage', {
            'imagePath': image.path,
          }) ??
          '';
    } catch (_) {
      return '';
    }
  }

  /// Structured page analysis (for advanced edit / region objects).
  /// Renders PDF page via MuPDF then runs DET + REC.
  static Future<List<PdfRegionObject>?> analyzePageStructured({
    required String pdfPath,
    required int page,
  }) async {
    if (!_initialized) {
      final ok = await initialize();
      if (!ok) return null;
    }
    try {
      String? imagePath;
      final rendered = await MuPdfService.renderPage(
        File(pdfPath),
        page: page,
        dpi: 144,
      );
      imagePath = rendered?.path;

      final raw = await _channel.invokeMethod<String>('analyzePage', {
        'pdfPath': pdfPath,
        'page': page,
        if (imagePath != null) 'imagePath': imagePath,
      });
      if (raw == null || raw.isEmpty) return null;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final engine = '${decoded['engine'] ?? ''}';
      final list = decoded['objects'];
      if (engine != 'pp_ocr' || list is! List || list.isEmpty) return null;
      final objects = list
          .whereType<Map>()
          .map((e) => PdfRegionObject.fromJson(Map<String, dynamic>.from(e)))
          .where((o) => _usableText(o.text, o.confidence))
          .toList();
      return objects.isEmpty ? null : objects;
    } catch (_) {
      return null;
    }
  }

  static bool _usableText(String text, double confidence) {
    final t = text.trim();
    if (t.isEmpty || confidence < 0.35) return false;
    final chars = t.runes.toList();
    if (chars.isEmpty) return false;
    var useful = 0;
    var symbols = 0;
    for (final r in chars) {
      final latin = (r >= 0x41 && r <= 0x5A) || (r >= 0x61 && r <= 0x7A);
      final digit = r >= 0x30 && r <= 0x39;
      final devanagari = r >= 0x0900 && r <= 0x097F;
      if (latin || digit || devanagari) {
        useful++;
      } else if (!(r == 0x20 || r == 0x09 || r == 0x0A ||
          r == 0x2E || r == 0x2C || r == 0x3A || r == 0x3B ||
          r == 0x2D || r == 0x2F || r == 0x28 || r == 0x29 ||
          r == 0x25 || r == 0x26 || r == 0x27 || r == 0x22)) {
        symbols++;
      }
    }
    if (useful == 0) return false;
    return symbols <= (chars.length * 0.45).floor();
  }

  static Future<void> unload() async {
    try {
      await _channel.invokeMethod('unload');
    } catch (_) {}
    _initialized = false;
  }
}
