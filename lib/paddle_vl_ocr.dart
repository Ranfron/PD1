import 'dart:io';
import 'package:flutter/services.dart';
import 'paddle_model_manager.dart';

/// Flutter ↔ native bridge for optional PaddleOCR-VL-1.6 (llama.cpp).
/// If native lib / model is missing, [isAvailable] is false and callers
/// should fall back to ML Kit.
class PaddleVlOcr {
  static const _channel = MethodChannel('com.pdfpower.app/paddle_vl');

  static bool _initialized = false;

  static Future<bool> isAvailable() async {
    final paths = await PaddleModelManager.activePaths();
    if (paths == null) return false;
    try {
      final ok = await _channel.invokeMethod<bool>('isReady') ?? false;
      return ok;
    } catch (_) {
      // Native side not linked yet — treat as unavailable.
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
    } catch (e) {
      _initialized = false;
      return false;
    }
  }

  /// Run OCR on an image file. Returns empty string on failure.
  static Future<String> processImage(File image) async {
    if (!_initialized) {
      final ok = await initialize();
      if (!ok) return '';
    }
    try {
      final text = await _channel.invokeMethod<String>('processImage', {
        'imagePath': image.path,
      });
      return text ?? '';
    } catch (_) {
      return '';
    }
  }

  static Future<void> unload() async {
    try {
      await _channel.invokeMethod('unload');
    } catch (_) {}
    _initialized = false;
  }
}
