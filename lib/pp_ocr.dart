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

  /// Hard ceiling on how long we wait for a single native call before giving
  /// up on it from the Dart side. The native layer has its own internal time
  /// budget (see PpOcrEngine.kt) that's shorter than this, so in the normal
  /// case native finishes (or bails out) first; this is the belt to that
  /// braces.
  ///
  /// Without a timeout here, one unusually slow/dense page could leave the
  /// OCR screen showing "Running OCR…" forever: the native side runs every
  /// call through a single-thread executor, so once a call is stuck, every
  /// OCR attempt afterwards just queues up behind it and never even starts.
  static const Duration _kInferenceTimeout = Duration(seconds: 55);
  static const Duration _kInitTimeout = Duration(seconds: 20);
  static const Duration _kPingTimeout = Duration(seconds: 10);

  static Future<bool> isAvailable() async {
    final paths = await PpOcrModelManager.activePaths();
    if (paths == null) return false;
    try {
      var ok = await _channel
              .invokeMethod<bool>('isReady')
              .timeout(_kPingTimeout, onTimeout: () => false) ??
          false;
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
      return await _channel
              .invokeMethod<bool>('nativeReady')
              .timeout(_kPingTimeout, onTimeout: () => false) ??
          false;
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
      }).timeout(_kInitTimeout, onTimeout: () => false);
      _initialized = ok == true;
      return _initialized;
    } catch (_) {
      _initialized = false;
      return false;
    }
  }

  /// Best-effort request to stop any in-flight native inference call as soon
  /// as possible. Safe to call even if nothing is running. Fire-and-forget:
  /// callers don't need (and shouldn't wait) for this to complete, since the
  /// whole point is to unblock the UI immediately rather than wait longer.
  static void cancel() {
    _channel.invokeMethod('cancel').catchError((_) => null);
  }

  /// Plain text OCR for a single image file.
  static Future<String> processImage(File image) async {
    if (!_initialized) {
      final ok = await initialize();
      if (!ok) return '';
    }
    try {
      final result = await _channel.invokeMethod<String>('processImage', {
        'imagePath': image.path,
      }).timeout(_kInferenceTimeout, onTimeout: () {
        cancel();
        return null;
      });
      return result ?? '';
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
      }).timeout(_kInferenceTimeout, onTimeout: () {
        cancel();
        return null;
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
