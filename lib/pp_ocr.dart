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
      return list
          .whereType<Map>()
          .map((e) => PdfRegionObject.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    } catch (_) {
      return null;
    }
  }

  static Future<void> unload() async {
    try {
      await _channel.invokeMethod('unload');
    } catch (_) {}
    _initialized = false;
  }
}
