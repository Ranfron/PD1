import 'package:shared_preferences/shared_preferences.dart';

/// OCR engine selection. ML Kit is always available.
/// PP-OCR = PP-OCRv6 Medium DET + devanagari_PP-OCRv5_mobile_rec (Hindi + English + numbers).
enum OcrEngineType { auto, mlkit, ppOcr }

class OcrEngine {
  static const _prefKey = 'ocr_engine';

  static Future<OcrEngineType> getSelected() async {
    final prefs = await SharedPreferences.getInstance();
    final v = prefs.getString(_prefKey) ?? 'auto';
    return OcrEngineType.values.firstWhere(
      (e) => e.name == v,
      orElse: () => OcrEngineType.auto,
    );
  }

  static Future<void> setSelected(OcrEngineType type) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefKey, type.name);
  }

  static String label(OcrEngineType t) {
    switch (t) {
      case OcrEngineType.auto:
        return 'Auto';
      case OcrEngineType.mlkit:
        return 'ML Kit';
      case OcrEngineType.ppOcr:
        return 'PP-OCR (Hindi + English)';
    }
  }

  static String subtitle(OcrEngineType t) {
    switch (t) {
      case OcrEngineType.auto:
        return 'ML Kit by default · PP-OCR if models installed';
      case OcrEngineType.mlkit:
        return 'Fast · Lightweight · No download';
      case OcrEngineType.ppOcr:
        return 'PP-OCRv6 Medium DET + Devanagari REC · Offline';
    }
  }
}
