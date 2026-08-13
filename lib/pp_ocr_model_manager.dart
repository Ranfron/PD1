import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'storage.dart';

/// Models for the final OCR pipeline:
///   DET  → PP-OCRv6 Medium DET
///   REC  → devanagari_PP-OCRv5_mobile_rec  (Hindi + English + numbers)
///
/// Prefer ONNX for Android ONNX Runtime / official PaddleOCR Android demo compatibility.
class PpOcrModelManager {
  static const _prefReady = 'pp_ocr_models_ready';

  // Detection
  static const detOnnxName = 'PP-OCRv6_medium_det.onnx';
  static const detSizeMbApprox = 62;

  // Recognition (Devanagari script → Hindi / Marathi / etc. + English + numbers)
  static const recOnnxName = 'devanagari_PP-OCRv5_mobile_rec.onnx';
  static const recDictName = 'ppocrv5_devanagari_dict.txt';
  static const recSizeMbApprox = 8;

  /// Official / community ONNX models (Hugging Face resolve links for direct download).
  /// Local filenames stay stable for the native engine.
  static const detUrl =
      'https://huggingface.co/PaddlePaddle/PP-OCRv6_medium_det_onnx/resolve/main/inference.onnx';
  static const recUrl =
      'https://huggingface.co/OllmOne/PP-OCRv5/resolve/main/devanagari_pp-ocrv5_mobile_rec.onnx';
  static const dictUrl =
      'https://huggingface.co/OllmOne/PP-OCRv5/resolve/main/ppocrv5_devanagari_dict.txt';

  static Future<Directory> modelsDir() => AppStorage.modelsDir();

  static Future<String> detPath() async {
    final dir = await modelsDir();
    return p.join(dir.path, detOnnxName);
  }

  static Future<String> recPath() async {
    final dir = await modelsDir();
    return p.join(dir.path, recOnnxName);
  }

  static Future<String> dictPath() async {
    final dir = await modelsDir();
    return p.join(dir.path, recDictName);
  }

  static Future<bool> isDetInstalled() async {
    final f = File(await detPath());
    return f.existsSync() && f.lengthSync() > 1024 * 1024;
  }

  static Future<bool> isRecInstalled() async {
    final f = File(await recPath());
    return f.existsSync() && f.lengthSync() > 512 * 1024;
  }

  static Future<bool> isDictInstalled() async {
    final f = File(await dictPath());
    if (!f.existsSync() || f.lengthSync() <= 100) return false;
    try {
      final lines = await f.readAsLines();
      return lines.length == 568 && lines.every((e) => e.isNotEmpty);
    } catch (_) {
      return false;
    }
  }

  static Future<bool> isReady() async {
    return await isDetInstalled() &&
        await isRecInstalled() &&
        await isDictInstalled();
  }

  static Future<({String det, String rec, String dict})?> activePaths() async {
    if (!await isReady()) return null;
    return (
      det: await detPath(),
      rec: await recPath(),
      dict: await dictPath(),
    );
  }

  static Future<void> downloadFile({
    required String url,
    required String destPath,
    void Function(double progress)? onProgress,
  }) async {
    final client = http.Client();
    try {
      final req = http.Request('GET', Uri.parse(url));
      final res = await client.send(req);
      if (res.statusCode != 200) {
        throw Exception('HTTP ${res.statusCode} for $url');
      }
      final total = res.contentLength ?? 0;
      final tmp = File('$destPath.part');
      if (await tmp.exists()) await tmp.delete();
      final sink = tmp.openWrite();
      var received = 0;
      try {
        await for (final chunk in res.stream) {
          sink.add(chunk);
          received += chunk.length;
          if (total > 0) onProgress?.call(received / total);
        }
      } finally {
        await sink.close();
      }
      if (received < 1024) {
        await tmp.delete();
        throw Exception('Downloaded file is too small: $url');
      }
      if (await File(destPath).exists()) await File(destPath).delete();
      await tmp.rename(destPath);
    } finally {
      client.close();
    }
  }

  static Future<void> downloadDet({void Function(double)? onProgress}) async {
    await downloadFile(
      url: detUrl,
      destPath: await detPath(),
      onProgress: onProgress,
    );
  }

  static Future<void> downloadRec({void Function(double)? onProgress}) async {
    await downloadFile(
      url: recUrl,
      destPath: await recPath(),
      onProgress: onProgress,
    );
  }

  static Future<void> downloadDict({void Function(double)? onProgress}) async {
    await downloadFile(
      url: dictUrl,
      destPath: await dictPath(),
      onProgress: onProgress,
    );
  }

  static Future<void> downloadAll({
    void Function(String stage, double progress)? onProgress,
  }) async {
    await downloadDet(onProgress: (p) => onProgress?.call('det', p));
    await downloadRec(onProgress: (p) => onProgress?.call('rec', p));
    await downloadDict(onProgress: (p) => onProgress?.call('dict', p));
  }

  static Future<void> deleteAll() async {
    for (final path in [await detPath(), await recPath(), await dictPath()]) {
      final f = File(path);
      if (await f.exists()) await f.delete();
    }
    // Also clean any leftover .part files
    final dir = await modelsDir();
    if (await dir.exists()) {
      await for (final e in dir.list()) {
        if (e is File && e.path.endsWith('.part')) await e.delete();
      }
    }
  }

  static Future<int> usedBytes() async {
    var total = 0;
    for (final path in [await detPath(), await recPath(), await dictPath()]) {
      final f = File(path);
      if (await f.exists()) total += await f.length();
    }
    return total;
  }

  static Future<void> markReadyCache(bool ready) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefReady, ready);
  }
}
