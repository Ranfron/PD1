import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

/// Central storage for PDF Power.
///
/// Preferred tree (public Documents):
///   /Documents/Pdf Power/
///     ├── Models/PaddleOCR-VL/   ← GGUF models
///     ├── Output/
///     │     ├── Merged/
///     │     ├── Split/
///     │     ├── Compressed/
///     │     ├── OCR/
///     │     ├── Converted/
///     │     └── Edited/
///     └── Scans/                ← optional pick root
///
/// Falls back to app support dir if public Documents is blocked.
class AppStorage {
  static const rootName = 'Pdf Power';

  static Directory? _root;

  /// Request best-effort storage access (Android).
  static Future<bool> ensureAccess() async {
    if (!Platform.isAndroid) return true;
    // Legacy
    await Permission.storage.request();
    // Android 13+ media
    await Permission.photos.request();
    // Full files access (sideload / advanced users)
    final manage = await Permission.manageExternalStorage.request();
    return manage.isGranted || await Permission.storage.isGranted;
  }

  /// Root: /storage/emulated/0/Documents/Pdf Power
  static Future<Directory> root() async {
    if (_root != null && await _root!.exists()) return _root!;

    Directory candidate;
    try {
      // Prefer public Documents
      final ext = Directory('/storage/emulated/0/Documents');
      if (await ext.exists()) {
        candidate = Directory(p.join(ext.path, rootName));
      } else {
        final docs = await getExternalStorageDirectory();
        if (docs != null) {
          // e.g. Android/data/.../files → walk up to emulated/0 if possible
          candidate = Directory(p.join('/storage/emulated/0/Documents', rootName));
        } else {
          final app = await getApplicationDocumentsDirectory();
          candidate = Directory(p.join(app.path, rootName));
        }
      }
    } catch (_) {
      final app = await getApplicationDocumentsDirectory();
      candidate = Directory(p.join(app.path, rootName));
    }

    if (!await candidate.exists()) {
      try {
        await candidate.create(recursive: true);
      } catch (_) {
        final app = await getApplicationDocumentsDirectory();
        candidate = Directory(p.join(app.path, rootName));
        await candidate.create(recursive: true);
      }
    }
    _root = candidate;
    return candidate;
  }

  static Future<Directory> _sub(List<String> parts) async {
    final r = await root();
    final d = Directory(p.joinAll([r.path, ...parts]));
    if (!await d.exists()) await d.create(recursive: true);
    return d;
  }

  static Future<Directory> modelsDir() =>
      _sub(['Models', 'PaddleOCR-VL']);

  static Future<Directory> outputMerged() => _sub(['Output', 'Merged']);
  static Future<Directory> outputSplit() => _sub(['Output', 'Split']);
  static Future<Directory> outputCompressed() => _sub(['Output', 'Compressed']);
  static Future<Directory> outputOcr() => _sub(['Output', 'OCR']);
  static Future<Directory> outputConverted() => _sub(['Output', 'Converted']);
  static Future<Directory> outputEdited() => _sub(['Output', 'Edited']);
  static Future<Directory> outputGeneral() => _sub(['Output']);

  /// Unique path inside an output folder.
  static Future<String> uniquePath(
    Future<Directory> Function() folder,
    String baseName,
    String ext,
  ) async {
    final dir = await folder();
    final safe = baseName.replaceAll(RegExp(r'[^\w\-.]'), '_');
    final ts = DateTime.now().millisecondsSinceEpoch;
    return p.join(dir.path, '${safe}_$ts.$ext');
  }

  static String formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }
}
