import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

class PdfFilePicker {
  /// Pick one or more PDF files.
  static Future<List<File>> pickPdfs({bool allowMultiple = false}) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
      allowMultiple: allowMultiple,
      withData: false,
    );

    if (result == null || result.files.isEmpty) return [];

    final files = <File>[];
    for (final f in result.files) {
      if (f.path != null) {
        files.add(File(f.path!));
      }
    }
    return files;
  }

  /// Pick images (for convert / OCR).
  static Future<List<File>> pickImages({bool allowMultiple = true}) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: allowMultiple,
      withData: false,
    );
    if (result == null) return [];
    return result.files
        .where((f) => f.path != null)
        .map((f) => File(f.path!))
        .toList();
  }

  /// Request storage permission (Android).
  static Future<bool> ensureStoragePermission() async {
    if (Platform.isAndroid) {
      final status = await Permission.storage.request();
      if (status.isGranted) return true;
      // Android 13+
      final photos = await Permission.photos.request();
      final media = await Permission.mediaLibrary.request();
      return photos.isGranted || media.isGranted || status.isGranted;
    }
    return true;
  }

  /// Get app documents directory for saving outputs.
  static Future<Directory> getOutputDir() async {
    final dir = await getApplicationDocumentsDirectory();
    final out = Directory(p.join(dir.path, 'PDF_Power_Output'));
    if (!await out.exists()) {
      await out.create(recursive: true);
    }
    return out;
  }

  /// Generate a unique output path.
  static Future<String> uniqueOutputPath(String baseName, String ext) async {
    final dir = await getOutputDir();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final safeName = baseName.replaceAll(RegExp(r'[^\w\-.]'), '_');
    return p.join(dir.path, '${safeName}_$timestamp.$ext');
  }

  /// Show a simple snackbar result.
  static void showResult(BuildContext context, String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red.shade800 : const Color(0xFF1565C0),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }
}
