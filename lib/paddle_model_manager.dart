import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'storage.dart';

/// Quant variants — community names (smaller). Official single GGUF also supported.
enum PaddleQuant {
  q4Km('Q4_K_M', 'PaddleOCR-VL-1.6-Q4_K_M.gguf', 286),
  q5Km('Q5_K_M', 'PaddleOCR-VL-1.6-Q5_K_M.gguf', 326),
  q6K('Q6_K', 'PaddleOCR-VL-1.6-Q6_K.gguf', 367),
  q8O('Q8_0', 'PaddleOCR-VL-1.6-Q8_0.gguf', 475),
  /// Official unquantized-style name from PaddlePaddle repo
  official('Official', 'PaddleOCR-VL-1.6-GGUF.gguf', 900);

  final String label;
  final String fileName;
  final int sizeMb;
  const PaddleQuant(this.label, this.fileName, this.sizeMb);
}

class PaddleModelManager {
  static const _prefQuant = 'paddle_quant';

  /// Community shared mmproj + official mmproj name both accepted.
  static const mmprojName = 'PaddleOCR-VL-1.6-mmproj.gguf';
  static const mmprojOfficial = 'PaddleOCR-VL-1.6-GGUF-mmproj.gguf';
  static const mmprojSizeMb = 841;

  static const communityBase =
      'https://huggingface.co/SanjeevSOLANKI/PaddleOCR-VL-1.6-GGUF/resolve/main';
  static const officialBase =
      'https://huggingface.co/PaddlePaddle/PaddleOCR-VL-1.6-GGUF/resolve/main';

  static Future<Directory> modelsDir() => AppStorage.modelsDir();

  static Future<String> quantPath(PaddleQuant q) async {
    final dir = await modelsDir();
    return p.join(dir.path, q.fileName);
  }

  static Future<String> mmprojPath() async {
    final dir = await modelsDir();
    final community = File(p.join(dir.path, mmprojName));
    if (await community.exists()) return community.path;
    final official = File(p.join(dir.path, mmprojOfficial));
    if (await official.exists()) return official.path;
    return community.path; // download target
  }

  static Future<bool> isQuantInstalled(PaddleQuant q) async {
    final f = File(await quantPath(q));
    return f.existsSync() && f.lengthSync() > 1024 * 1024;
  }

  static Future<bool> isMmprojInstalled() async {
    final f = File(await mmprojPath());
    return f.existsSync() && f.lengthSync() > 1024 * 1024;
  }

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

  static Future<({String model, String mmproj})?> activePaths() async {
    if (!await isMmprojInstalled()) return null;
    final q = await selectedQuant();
    if (await isQuantInstalled(q)) {
      return (model: await quantPath(q), mmproj: await mmprojPath());
    }
    for (final alt in PaddleQuant.values) {
      if (await isQuantInstalled(alt)) {
        return (model: await quantPath(alt), mmproj: await mmprojPath());
      }
    }
    return null;
  }

  static String _urlFor(PaddleQuant q) {
    if (q == PaddleQuant.official) {
      return '$officialBase/${q.fileName}';
    }
    return '$communityBase/${q.fileName}';
  }

  static String _mmprojUrl(String fileName) {
    if (fileName == mmprojOfficial) {
      return '$officialBase/$mmprojOfficial';
    }
    return '$communityBase/$mmprojName';
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
        throw Exception('HTTP ${res.statusCode}');
      }
      final total = res.contentLength ?? 0;
      final tmp = File('$destPath.part');
      final sink = tmp.openWrite();
      var received = 0;
      await for (final chunk in res.stream) {
        sink.add(chunk);
        received += chunk.length;
        if (total > 0) onProgress?.call(received / total);
      }
      await sink.close();
      await tmp.rename(destPath);
    } finally {
      client.close();
    }
  }

  static Future<void> downloadQuant(
    PaddleQuant q, {
    void Function(double)? onProgress,
  }) async {
    await downloadFile(
      url: _urlFor(q),
      destPath: await quantPath(q),
      onProgress: onProgress,
    );
  }

  static Future<void> downloadMmproj({void Function(double)? onProgress}) async {
    // Prefer community shared mmproj name for Q4–Q8
    final dest = p.join((await modelsDir()).path, mmprojName);
    await downloadFile(
      url: _mmprojUrl(mmprojName),
      destPath: dest,
      onProgress: onProgress,
    );
  }

  static Future<void> deleteQuant(PaddleQuant q) async {
    final f = File(await quantPath(q));
    if (await f.exists()) await f.delete();
  }

  static Future<void> deleteMmproj() async {
    final dir = await modelsDir();
    for (final name in [mmprojName, mmprojOfficial]) {
      final f = File(p.join(dir.path, name));
      if (await f.exists()) await f.delete();
    }
  }

  static Future<void> deleteAll() async {
    final dir = await modelsDir();
    if (await dir.exists()) {
      await for (final e in dir.list()) {
        if (e is File) await e.delete();
      }
    }
  }

  static Future<int> usedBytes() async {
    final dir = await modelsDir();
    if (!await dir.exists()) return 0;
    var total = 0;
    await for (final e in dir.list()) {
      if (e is File) total += await e.length();
    }
    return total;
  }
}
