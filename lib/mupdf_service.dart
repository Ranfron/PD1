import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'file_picker.dart';

/// Flutter bridge to MuPDF 1.28.x advanced operations.
class MuPdfService {
  static const _channel = MethodChannel('com.pdfpower.app/mupdf');
  static bool? _available;

  static Future<bool> isAvailable() async {
    if (_available != null) return _available!;
    try {
      _available = await _channel.invokeMethod<bool>('isAvailable') == true;
    } catch (_) {
      _available = false;
    }
    return _available!;
  }

  static Future<T?> _invoke<T>(String method, Map<String, dynamic> args) async {
    if (!await isAvailable()) return null;
    try {
      return await _channel.invokeMethod<T>(method, args);
    } catch (_) {
      return null;
    }
  }

  static Future<int?> pageCount(String path) =>
      _invoke<int>('pageCount', {'path': path});

  static Future<Map<String, dynamic>?> info(String path) async {
    final r = await _invoke<Map>('info', {'path': path});
    return r?.map((k, v) => MapEntry(k.toString(), v));
  }

  static Future<File?> merge(List<File> files, {String? outputName}) async {
    if (files.length < 2) return null;
    final outPath =
        await PdfFilePicker.uniqueMergedPath(outputName ?? 'merged');
    final path = await _invoke<String>('merge', {
      'paths': files.map((f) => f.path).toList(),
      'outPath': outPath,
    });
    return _file(path);
  }

  static Future<File?> split(File source,
      {required int start, required int end, String? outputName}) async {
    final base = p.basenameWithoutExtension(source.path);
    final outPath = await PdfFilePicker.uniqueSplitPath(
        outputName ?? '${base}_p$start-$end');
    final path = await _invoke<String>('split', {
      'path': source.path,
      'outPath': outPath,
      'start': start,
      'end': end,
    });
    return _file(path);
  }

  static Future<File?> compress(File source, {String? outputName}) async {
    final base = p.basenameWithoutExtension(source.path);
    final outPath = await PdfFilePicker.uniqueCompressedPath(
        outputName ?? '${base}_compressed');
    final path = await _invoke<String>('compress', {
      'path': source.path,
      'outPath': outPath,
    });
    return _file(path);
  }

  static Future<String?> extractText(File source,
      {int start = 1, int? end}) async {
    return _invoke<String>('extractText', {
      'path': source.path,
      'start': start,
      if (end != null) 'end': end,
    });
  }

  static Future<File?> deletePages(File source,
      {required int start, required int end}) async {
    final base = p.basenameWithoutExtension(source.path);
    final outPath = await PdfFilePicker.uniqueEditedPath('${base}_del');
    final path = await _invoke<String>('deletePages', {
      'path': source.path,
      'outPath': outPath,
      'start': start,
      'end': end,
    });
    return _file(path);
  }

  static Future<File?> rotatePages(File source,
      {int start = 1, int end = -1, int degrees = 90}) async {
    final base = p.basenameWithoutExtension(source.path);
    final outPath =
        await PdfFilePicker.uniqueEditedPath('${base}_rot$degrees');
    final path = await _invoke<String>('rotatePages', {
      'path': source.path,
      'outPath': outPath,
      'start': start,
      'end': end,
      'degrees': degrees,
    });
    return _file(path);
  }

  static Future<File?> addBlankPage(File source, {int index = -1}) async {
    final base = p.basenameWithoutExtension(source.path);
    final outPath = await PdfFilePicker.uniqueEditedPath('${base}_blank');
    final path = await _invoke<String>('addBlankPage', {
      'path': source.path,
      'outPath': outPath,
      'index': index,
    });
    return _file(path);
  }

  static Future<File?> encrypt(File source,
      {required String userPassword, String ownerPassword = ''}) async {
    final base = p.basenameWithoutExtension(source.path);
    final outPath = await PdfFilePicker.uniqueEditedPath('${base}_locked');
    final path = await _invoke<String>('encrypt', {
      'path': source.path,
      'outPath': outPath,
      'userPassword': userPassword,
      'ownerPassword': ownerPassword,
    });
    return _file(path);
  }

  static Future<File?> setMetadata(
      File source, Map<String, String> meta) async {
    final base = p.basenameWithoutExtension(source.path);
    final outPath = await PdfFilePicker.uniqueEditedPath('${base}_meta');
    final path = await _invoke<String>('setMetadata', {
      'path': source.path,
      'outPath': outPath,
      'meta': meta,
    });
    return _file(path);
  }

  static Future<File?> watermarkText(
    File source, {
    required String text,
    int start = 1,
    int end = -1,
    double opacity = 0.25,
    int rotation = 45,
  }) async {
    final base = p.basenameWithoutExtension(source.path);
    final outPath = await PdfFilePicker.uniqueEditedPath('${base}_wm');
    final path = await _invoke<String>('watermarkText', {
      'path': source.path,
      'outPath': outPath,
      'text': text,
      'start': start,
      'end': end,
      'opacity': opacity,
      'rotation': rotation,
    });
    return _file(path);
  }

  static Future<File?> addRedaction(
    File source, {
    required int page,
    required double x0,
    required double y0,
    required double x1,
    required double y1,
  }) async {
    final base = p.basenameWithoutExtension(source.path);
    final outPath = await PdfFilePicker.uniqueEditedPath('${base}_redact');
    final path = await _invoke<String>('addRedaction', {
      'path': source.path,
      'outPath': outPath,
      'page': page,
      'x0': x0,
      'y0': y0,
      'x1': x1,
      'y1': y1,
    });
    return _file(path);
  }

  static Future<File?> applyRedactions(File source) async {
    final base = p.basenameWithoutExtension(source.path);
    final outPath = await PdfFilePicker.uniqueEditedPath('${base}_redacted');
    final path = await _invoke<String>('applyRedactions', {
      'path': source.path,
      'outPath': outPath,
    });
    return _file(path);
  }

  static Future<File?> flatten(File source) async {
    final base = p.basenameWithoutExtension(source.path);
    final outPath = await PdfFilePicker.uniqueEditedPath('${base}_flat');
    final path = await _invoke<String>('flatten', {
      'path': source.path,
      'outPath': outPath,
    });
    return _file(path);
  }


  static Future<File?> addFreeText(
    File source, {
    required int page,
    required String text,
    double x0 = 50,
    double y0 = 50,
    double x1 = 250,
    double y1 = 100,
  }) async {
    final base = p.basenameWithoutExtension(source.path);
    final outPath = await PdfFilePicker.uniqueEditedPath('${base}_text');
    final path = await _invoke<String>('addFreeText', {
      'path': source.path,
      'outPath': outPath,
      'page': page,
      'text': text,
      'x0': x0,
      'y0': y0,
      'x1': x1,
      'y1': y1,
    });
    return _file(path);
  }

  static Future<File?> addStampImage(
    File source, {
    required File image,
    required int page,
    double x0 = 50,
    double y0 = 50,
    double x1 = 200,
    double y1 = 150,
  }) async {
    final base = p.basenameWithoutExtension(source.path);
    final outPath = await PdfFilePicker.uniqueEditedPath('${base}_img');
    final path = await _invoke<String>('addStampImage', {
      'path': source.path,
      'outPath': outPath,
      'imagePath': image.path,
      'page': page,
      'x0': x0,
      'y0': y0,
      'x1': x1,
      'y1': y1,
    });
    return _file(path);
  }

  static Future<File?> addTextField(
    File source, {
    required int page,
    required String name,
    String value = '',
    double x0 = 50,
    double y0 = 50,
    double x1 = 250,
    double y1 = 80,
  }) async {
    final base = p.basenameWithoutExtension(source.path);
    final outPath = await PdfFilePicker.uniqueEditedPath('${base}_field');
    final path = await _invoke<String>('addTextField', {
      'path': source.path,
      'outPath': outPath,
      'page': page,
      'name': name,
      'value': value,
      'x0': x0,
      'y0': y0,
      'x1': x1,
      'y1': y1,
    });
    return _file(path);
  }


    static Future<File?> renderPage(
    File source, {
    int page = 1,
    int dpi = 144,
  }) async {
    final base = p.basenameWithoutExtension(source.path);
    final dir = await PdfFilePicker.uniqueEditedPath('${base}_render');
    final pngPath = dir.replaceAll('.pdf', '') + '_p$page.png';
    final path = await _invoke<String>('renderPage', {
      'path': source.path,
      'outPath': pngPath,
      'page': page,
      'dpi': dpi,
    });
    return _file(path);
  }

static Future<({double width, double height})?> pageSize(
    File source, {
    int page = 1,
  }) async {
    final r = await _invoke<Map>('pageSize', {
      'path': source.path,
      'page': page,
    });
    if (r == null) return null;
    return (
      width: (r['width'] as num?)?.toDouble() ?? 595,
      height: (r['height'] as num?)?.toDouble() ?? 842,
    );
  }

  static File? _file(String? path) {
    if (path == null) return null;
    final f = File(path);
    return f.existsSync() ? f : null;
  }
}
