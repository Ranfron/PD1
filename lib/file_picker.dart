import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'storage.dart';

class PdfFilePicker {
  static Future<List<File>> pickPdfs({bool allowMultiple = false}) async {
    await AppStorage.ensureAccess();
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
      allowMultiple: allowMultiple,
      withData: false,
    );
    if (result == null || result.files.isEmpty) return [];
    return result.files
        .where((f) => f.path != null)
        .map((f) => File(f.path!))
        .toList();
  }

  static Future<List<File>> pickImages({bool allowMultiple = true}) async {
    await AppStorage.ensureAccess();
    final result = await FilePicker.pickFiles(
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

  static Future<bool> ensureStoragePermission() => AppStorage.ensureAccess();

  static Future<Directory> getOutputDir() => AppStorage.outputGeneral();

  static Future<String> uniqueOutputPath(String baseName, String ext) async {
    return AppStorage.uniquePath(AppStorage.outputGeneral, baseName, ext);
  }

  static Future<String> uniqueMergedPath(String baseName) =>
      AppStorage.uniquePath(AppStorage.outputMerged, baseName, 'pdf');

  static Future<String> uniqueSplitPath(String baseName) =>
      AppStorage.uniquePath(AppStorage.outputSplit, baseName, 'pdf');

  static Future<String> uniqueCompressedPath(String baseName) =>
      AppStorage.uniquePath(AppStorage.outputCompressed, baseName, 'pdf');

  static Future<String> uniqueOcrPath(String baseName) =>
      AppStorage.uniquePath(AppStorage.outputOcr, baseName, 'pdf');

  static Future<String> uniqueConvertedPath(String baseName) =>
      AppStorage.uniquePath(AppStorage.outputConverted, baseName, 'pdf');

  static Future<String> uniqueEditedPath(String baseName) =>
      AppStorage.uniquePath(AppStorage.outputEdited, baseName, 'pdf');

  static void showResult(BuildContext context, String message,
      {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor:
            isError ? Colors.red.shade800 : const Color(0xFF1565C0),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }
}
