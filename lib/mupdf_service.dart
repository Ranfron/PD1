import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'file_picker.dart';

/// Flutter bridge to native MuPDF 1.28.x (com.artifex.mupdf:fitz).
/// Falls back gracefully if native side is unavailable.
class MuPdfService {
  static const _channel = MethodChannel('com.pdfpower.app/mupdf');

  static bool? _available;

  static Future<bool> isAvailable() async {
    if (_available != null) return _available!;
    try {
      final v = await _channel.invokeMethod<bool>('isAvailable');
      _available = v == true;
    } catch (_) {
      _available = false;
    }
    return _available!;
  }

  static Future<String?> version() async {
    try {
      return await _channel.invokeMethod<String>('version');
    } catch (_) {
      return null;
    }
  }

  static Future<int?> pageCount(String path) async {
    try {
      return await _channel.invokeMethod<int>('pageCount', {'path': path});
    } catch (_) {
      return null;
    }
  }

  static Future<Map<String, dynamic>?> info(String path) async {
    try {
      final r = await _channel.invokeMethod<Map>('info', {'path': path});
      return r?.map((k, v) => MapEntry(k.toString(), v));
    } catch (_) {
      return null;
    }
  }

  /// Native MuPDF merge. Returns output [File] or null on failure.
  static Future<File?> merge(List<File> files, {String? outputName}) async {
    if (files.length < 2) return null;
    if (!await isAvailable()) return null;
    final outPath = await PdfFilePicker.uniqueOutputPath(
      outputName ?? 'merged_mupdf',
      'pdf',
    );
    try {
      final path = await _channel.invokeMethod<String>('merge', {
        'paths': files.map((f) => f.path).toList(),
        'outPath': outPath,
      });
      if (path == null) return null;
      final f = File(path);
      return f.existsSync() ? f : null;
    } catch (_) {
      return null;
    }
  }

  /// Extract pages [start]–[end] (1-based inclusive) into a new PDF.
  static Future<File?> split(
    File source, {
    required int start,
    required int end,
    String? outputName,
  }) async {
    if (!await isAvailable()) return null;
    final base = p.basenameWithoutExtension(source.path);
    final outPath = await PdfFilePicker.uniqueOutputPath(
      outputName ?? '${base}_p$start-$end',
      'pdf',
    );
    try {
      final path = await _channel.invokeMethod<String>('split', {
        'path': source.path,
        'outPath': outPath,
        'start': start,
        'end': end,
      });
      if (path == null) return null;
      final f = File(path);
      return f.existsSync() ? f : null;
    } catch (_) {
      return null;
    }
  }

  /// Compress via MuPDF clean/garbage/compress save options.
  static Future<File?> compress(File source, {String? outputName}) async {
    if (!await isAvailable()) return null;
    final base = p.basenameWithoutExtension(source.path);
    final outPath = await PdfFilePicker.uniqueOutputPath(
      outputName ?? '${base}_compressed',
      'pdf',
    );
    try {
      final path = await _channel.invokeMethod<String>('compress', {
        'path': source.path,
        'outPath': outPath,
      });
      if (path == null) return null;
      final f = File(path);
      return f.existsSync() ? f : null;
    } catch (_) {
      return null;
    }
  }
}
