import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';

enum ScanMode { document, card }

/// Flutter ↔ native document scanner (detect / auto-capture / enhance).
class ScannerEngine {
  static const _channel = MethodChannel('com.pdfpower.app/scanner');

  static Future<Map<String, dynamic>?> detectDocument(
    File image, {
    ScanMode mode = ScanMode.document,
  }) async {
    try {
      final raw = await _channel.invokeMethod<String>('detectDocument', {
        'imagePath': image.path,
        'mode': mode == ScanMode.card ? 'card' : 'document',
      });
      if (raw == null || raw.isEmpty) return null;
      final m = jsonDecode(raw);
      if (m is Map<String, dynamic>) return m;
      if (m is Map) return Map<String, dynamic>.from(m);
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Crop + perspective (AABB) + enhance. Returns output JPEG path.
  static Future<File?> processScan(
    File image, {
    ScanMode mode = ScanMode.document,
    bool enhance = true,
    bool bw = false,
    String? outDir,
  }) async {
    try {
      final path = await _channel.invokeMethod<String>('processScan', {
        'imagePath': image.path,
        'mode': mode == ScanMode.card ? 'card' : 'document',
        'enhance': enhance,
        'bw': bw,
        if (outDir != null) 'outDir': outDir,
      });
      if (path == null || path.isEmpty) return null;
      final f = File(path);
      return await f.exists() ? f : null;
    } catch (_) {
      return null;
    }
  }

  static Future<void> resetAutoCapture() async {
    try {
      await _channel.invokeMethod('resetAutoCapture');
    } catch (_) {}
  }

  static Future<bool> checkStable(
    File frame, {
    ScanMode mode = ScanMode.document,
  }) async {
    try {
      return await _channel.invokeMethod<bool>('checkStable', {
            'imagePath': frame.path,
            'mode': mode == ScanMode.card ? 'card' : 'document',
          }) ??
          false;
    } catch (_) {
      return false;
    }
  }
}
