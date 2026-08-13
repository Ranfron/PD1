# PDF Power – Advanced Offline PDF Editor

Full offline Flutter PDF editor APK.

## Features

| Tool | Description |
|------|-------------|
| **Viewer** | High-quality PDF viewing (pdfrx / MuPDF-based) |
| **Merge** | Combine multiple PDFs |
| **Split** | Extract page ranges |
| **Compress** | Reduce file size |
| **Convert** | Images → PDF |
| **OCR** | On-device text extraction (ML Kit) |
| **Annotate** | Draw / highlight overlay |
| **Settings** | Preferences & output folder |

**100% Offline** – no cloud, no telemetry. Files stay on device.

## Architecture

```
PDF POWER APP
     │
Flutter UI
     │
┌────┴────┐
│         │
PDF Engine   OCR Engine
(pdfrx +     (ML Kit /
 pure Dart)   PaddleOCR ready)
     │
Android Native + Local Storage
```

Native engines (MuPDF, qpdf, PDFBox, PaddleOCR PP-OCRv6) can be added later via MethodChannels for production-grade binary operations.

## Build on GitHub Actions

1. Push this repo to GitHub
2. Go to **Actions** tab
3. Run workflow **Build PDF Power APK** (or push to `main`)
4. Download artifact **pdf-power-apk**

Or build locally:

```bash
flutter pub get
flutter build apk --release
```

APK output: `build/app/outputs/flutter-apk/`

## Requirements

- Flutter 3.22+
- Android SDK 24+
- Java 17

## Project Structure

```
lib/
├── main.dart
├── home.dart
├── viewer.dart
├── tools.dart
├── file_picker.dart
├── pdf_service.dart
├── merge.dart
├── split.dart
├── compress.dart
├── convert.dart
├── ocr.dart
├── annotate.dart
└── settings.dart
```

## License

MIT – free for personal & commercial use.

## Phase 3 — Real PaddleOCR-VL (optional)

Native bridge validates GGUF files on `initialize()`. Full token inference needs:

```bash
cd android/app/src/main/cpp/third_party
git clone --depth 1 https://github.com/ggerganov/llama.cpp.git
```

Then uncomment the `HAS_LLAMA` block in `CMakeLists.txt` and implement load/infer in `paddle_vl_stub.cpp`.

Until then: models download + GGUF validation work; page OCR uses **ML Kit** object map after MuPDF render.


## Native PaddleOCR-VL 1.6

When GitHub Actions clones llama.cpp, the Android native layer builds llama.cpp + libmtmd and loads the PaddleOCR-VL GGUF text model together with its mmproj. Page analysis uses MTMD image decoding and the PaddleOCR-VL `Spotting:` task; failures return an empty object list so the existing ML Kit/MuPDF fallback remains active.
