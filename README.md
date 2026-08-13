# PDF Power – Advanced Offline PDF Editor

Full offline Flutter PDF editor + document scanner + PP-OCR.

## Features

| Tool | Description |
|------|-------------|
| **Viewer** | High-quality PDF viewing (pdfrx / MuPDF) |
| **Merge / Split / Compress** | Core PDF tools |
| **Convert** | Images → PDF |
| **Scanner** | CameraX-style capture · document/card mode · auto enhance |
| **OCR** | PP-OCRv6 Medium DET + Devanagari REC · ML Kit fallback |
| **Annotate / Advanced / Pro** | Edit tools |
| **Settings** | Preferences |

**100% Offline** after models are on device.

## OCR (real ONNX inference)

```
Image / PDF page
      ↓
PP-OCRv6 Medium DET   (ONNX Runtime, Kotlin)
      ↓
text boxes
      ↓
devanagari_PP-OCRv5_mobile_rec
      ↓
Hindi + English + Numbers
      ↓
JSON objects / plain text
      ↓ (empty)
ML Kit fallback
```

Implementation: `android/.../ocr/PpOcrEngine.kt`  
Bridge: `PpOcrBridge.kt` · Flutter: `pp_ocr.dart`

Models (download in OCR → Manage PP-OCR Models):

| File | Role |
|------|------|
| `PP-OCRv6_medium_det.onnx` | Detection |
| `devanagari_PP-OCRv5_mobile_rec.onnx` | Recognition |
| `ppocrv5_devanagari_dict.txt` | Charset |

Place under `Documents/Pdf Power/Models/`. Export with `paddle2onnx` if Hugging Face URLs differ.

## Scanner

```
Camera / Gallery
      ↓
OpenCV DocumentDetector (contour + four-corner quad)
      ↓
AutoCaptureController (stable corners)
      ↓
PerspectiveCorrector + enhance / B&W
      ↓
same PP-OCR engine
```

- **Document mode** — A4, forms, certificates, receipts, notes  
- **Card mode** — Aadhaar, PAN, licence, business card  

Native: `scanner/DocumentDetector.kt`, `PerspectiveCorrector.kt`, `AutoCaptureController.kt`, `ScannerBridge.kt`  
Flutter: `scanner.dart`, `scanner_engine.dart`

OpenCV 4.9.0 is used for contour detection and true four-point perspective correction. The Flutter scanner API remains independent of the native implementation.

## Build

```bash
flutter pub get
flutter build apk --release --target-platform android-arm64
```

GitHub Actions: workflow **Build APK (arm64-v8a)**.

## Requirements

- Flutter 3.22+
- minSdk 24 · arm64-v8a
- Java 17
- Camera permission for Scanner

## License

MIT
