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
    return f.existsSync() && f.lengthSync() > 100;
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

  /// Downloads [url] to [destPath], resuming an interrupted attempt instead
  /// of starting over.
  ///
  /// Previously this always opened the destination in overwrite mode and
  /// sent a plain GET with no `Range` header, so any connection drop meant
  /// the next attempt silently re-downloaded the whole file from byte zero.
  /// Now a `<dest>.part` file is treated as a resume point: we ask the
  /// server for `Range: bytes=<existing>-` and append to it. If the server
  /// doesn't honor the range (some CDNs ignore it and send back a full 200
  /// response), we detect that and fall back to a clean restart rather than
  /// corrupting the file by appending full content after existing bytes.
  ///
  /// A `.part` file is only ever deleted/renamed on confirmed success, so a
  /// failed attempt (network drop, app killed, etc.) always leaves something
  /// the next attempt can resume from.
  static Future<void> downloadFile({
    required String url,
    required String destPath,
    void Function(double progress)? onProgress,
    int maxRetries = 5,
  }) async {
    final tmp = File('$destPath.part');
    Object? lastError;

    for (var attempt = 1; attempt <= maxRetries; attempt++) {
      final client = http.Client();
      try {
        var existing = await tmp.exists() ? await tmp.length() : 0;

        final req = http.Request('GET', Uri.parse(url));
        if (existing > 0) {
          req.headers['Range'] = 'bytes=$existing-';
        }
        final res = await client.send(req);

        if (res.statusCode == 416) {
          // Server says our resume point is invalid (e.g. the .part file
          // was already complete, or doesn't match anymore). Start clean.
          await tmp.delete();
          throw Exception('Range not satisfiable, restarting');
        }
        if (res.statusCode == 200 && existing > 0) {
          // Server ignored the Range header and is sending the full file
          // again — appending would corrupt it, so restart from scratch.
          existing = 0;
          await tmp.delete();
        } else if (res.statusCode != 200 && res.statusCode != 206) {
          throw Exception('HTTP ${res.statusCode} for $url');
        }

        int? total;
        final contentRange = res.headers['content-range'];
        if (contentRange != null && contentRange.contains('/')) {
          total = int.tryParse(contentRange.split('/').last);
        }
        total ??= res.contentLength != null ? res.contentLength! + existing : null;

        final sink = tmp.openWrite(
          mode: existing > 0 ? FileMode.append : FileMode.write,
        );
        var received = existing;
        try {
          await for (final chunk in res.stream) {
            sink.add(chunk);
            received += chunk.length;
            if (total != null && total > 0) {
              onProgress?.call((received / total).clamp(0.0, 1.0));
            }
          }
        } finally {
          await sink.flush();
          await sink.close();
        }

        if (total != null && received < total) {
          // Stream ended early (dropped connection) — keep the .part file
          // as-is so the next attempt resumes right from here.
          throw Exception('Incomplete download ($received / $total bytes)');
        }

        if (await File(destPath).exists()) {
          await File(destPath).delete();
        }
        await tmp.rename(destPath);
        return; // success
      } catch (e) {
        lastError = e;
        if (attempt >= maxRetries) rethrow;
        await Future.delayed(Duration(seconds: 2 * attempt));
      } finally {
        client.close();
      }
    }
    if (lastError != null) throw lastError;
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
