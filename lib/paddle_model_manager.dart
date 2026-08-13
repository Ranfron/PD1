import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Quantization variants for PaddleOCR-VL-1.6 (GGUF).
enum PaddleQuant {
  q4Km('Q4_K_M', 'q4_k_m.gguf', 286),
  q5Km('Q5_K_M', 'q5_k_m.gguf', 326),
  q6K('Q6_K', 'q6_k.gguf', 367),
  q8O('Q8_0', 'q8_0.gguf', 475);

  final String label;
  final String fileName;
  final int sizeMb;
  const PaddleQuant(this.label, this.fileName, this.sizeMb);
}

/// Manages download / delete / verify of optional PaddleOCR-VL models.
/// Models are NOT bundled in the APK.
class PaddleModelManager {
  static const _prefQuant = 'paddle_quant';
  static const _mmprojName = 'mmproj.gguf';

  /// Placeholder base URL — replace with real host when models are published.
  /// Expected layout:
  ///   {base}/paddleocr-vl-1.6/q4_k_m.gguf
  ///   {base}/paddleocr-vl-1.6/mmproj.gguf
  static const modelBaseUrl =
      'https://huggingface.co/your-org/PaddleOCR-VL-1.6-GGUF/resolve/main';

  static Future<Directory> modelsDir() async {
    final root = await getApplicationSupportDirectory();
    final dir = Directory(p.join(root.path, 'models', 'paddleocr-vl-1.6'));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  static Future<String> quantPath(PaddleQuant q) async {
    final dir = await modelsDir();
    return p.join(dir.path, q.fileName);
  }

  static Future<String> mmprojPath() async {
    final dir = await modelsDir();
    return p.join(dir.path, _mmprojName);
  }

  static Future<bool> isQuantInstalled(PaddleQuant q) async {
    final f = File(await quantPath(q));
    return f.existsSync() && f.lengthSync() > 1024 * 1024;
  }

  static Future<bool> isMmprojInstalled() async {
    final f = File(await mmprojPath());
    return f.existsSync() && f.lengthSync() > 1024 * 1024;
  }

  /// True when at least one quant + mmproj are present.
  static Future<bool> isReady() async {
    if (!await isMmprojInstalled()) return false;
    for (final q in PaddleQuant.values) {
      if (await isQuantInstalled(q)) return true;
    }
    return false;
  }

  static Future<PaddleQuant> selectedQuant() async {
    final prefs = await SharedPreferences.getInstance();
    final name = prefs.getString(_prefQuant) ?? PaddleQuant.q4Km.name;
    return PaddleQuant.values.firstWhere(
      (e) => e.name == name,
      orElse: () => PaddleQuant.q4Km,
    );
  }

  static Future<void> setSelectedQuant(PaddleQuant q) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefQuant, q.name);
  }

  /// Active model paths for native bridge (null if not ready).
  static Future<({String model, String mmproj})?> activePaths() async {
    if (!await isMmprojInstalled()) return null;
    final q = await selectedQuant();
    if (!await isQuantInstalled(q)) {
      // fallback to any installed quant
      for (final alt in PaddleQuant.values) {
        if (await isQuantInstalled(alt)) {
          return (model: await quantPath(alt), mmproj: await mmprojPath());
        }
      }
      return null;
    }
    return (model: await quantPath(q), mmproj: await mmprojPath());
  }

  /// Download a file with progress callback (0.0 – 1.0).
  static Future<void> downloadFile({
    required String url,
    required String destPath,
    void Function(double progress)? onProgress,
    void Function()? onDone,
  }) async {
    final client = http.Client();
    try {
      final req = http.Request('GET', Uri.parse(url));
      final res = await client.send(req);
      if (res.statusCode != 200) {
        throw Exception('Download failed: HTTP ${res.statusCode}');
      }
      final total = res.contentLength ?? 0;
      final file = File(destPath);
      final sink = file.openWrite();
      var received = 0;
      await for (final chunk in res.stream) {
        sink.add(chunk);
        received += chunk.length;
        if (total > 0 && onProgress != null) {
          onProgress(received / total);
        }
      }
      await sink.close();
      onDone?.call();
    } finally {
      client.close();
    }
  }

  static Future<void> downloadQuant(
    PaddleQuant q, {
    void Function(double)? onProgress,
  }) async {
    final url = '$modelBaseUrl/${q.fileName}';
    final dest = await quantPath(q);
    await downloadFile(url: url, destPath: dest, onProgress: onProgress);
  }

  static Future<void> downloadMmproj({void Function(double)? onProgress}) async {
    final url = '$modelBaseUrl/$_mmprojName';
    final dest = await mmprojPath();
    await downloadFile(url: url, destPath: dest, onProgress: onProgress);
  }

  static Future<void> deleteQuant(PaddleQuant q) async {
    final f = File(await quantPath(q));
    if (await f.exists()) await f.delete();
  }

  static Future<void> deleteMmproj() async {
    final f = File(await mmprojPath());
    if (await f.exists()) await f.delete();
  }

  static Future<void> deleteAll() async {
    final dir = await modelsDir();
    if (await dir.exists()) await dir.delete(recursive: true);
  }

  static Future<int> usedBytes() async {
    final dir = await modelsDir();
    if (!await dir.exists()) return 0;
    var total = 0;
    await for (final e in dir.list(recursive: true)) {
      if (e is File) total += await e.length();
    }
    return total;
  }
}
