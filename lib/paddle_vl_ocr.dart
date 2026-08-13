import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'paddle_model_manager.dart';
import 'pdf_edit_engine.dart';
import 'mupdf_service.dart';

/// Flutter ↔ native bridge for optional PaddleOCR-VL-1.6.
class PaddleVlOcr {
  static const _channel = MethodChannel('com.pdfpower.app/paddle_vl');
  static bool _initialized = false;

  static Future<bool> isAvailable() async {
    final paths = await PaddleModelManager.activePaths();
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
    final paths = await PaddleModelManager.activePaths();
    if (paths == null) return false;
    try {
      final ok = await _channel.invokeMethod<bool>('initialize', {
        'modelPath': paths.model,
        'mmprojPath': paths.mmproj,
      });
      _initialized = ok == true;
      return _initialized;
    } catch (_) {
      _initialized = false;
      return false;
    }
  }

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

  /// Structured analysis: render PDF page → nativeAnalyzePage / empty → parse objects.
  static Future<List<PdfRegionObject>?> analyzePageStructured({
    required String pdfPath,
    required int page,
  }) async {
    if (!_initialized) {
      final ok = await initialize();
      if (!ok) return null;
    }
    try {
      // Prefer raster for VL models
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
      if (engine != 'paddle_vl_spotting' || list is! List || list.isEmpty) return null;
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
