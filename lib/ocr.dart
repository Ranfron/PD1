import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gap/gap.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';
import 'file_picker.dart';
import 'pdf_service.dart';
import 'tools.dart';

class OcrPage extends StatefulWidget {
  const OcrPage({super.key});

  @override
  State<OcrPage> createState() => _OcrPageState();
}

class _OcrPageState extends State<OcrPage> {
  File? _image;
  String _extracted = '';
  bool _processing = false;
  final TextRecognizer _recognizer = TextRecognizer(script: TextRecognitionScript.latin);

  @override
  void dispose() {
    _recognizer.close();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final imgs = await PdfFilePicker.pickImages(allowMultiple: false);
    if (imgs.isNotEmpty) {
      setState(() {
        _image = imgs.first;
        _extracted = '';
      });
    }
  }

  Future<void> _runOcr() async {
    if (_image == null) return;
    setState(() => _processing = true);
    try {
      final input = InputImage.fromFile(_image!);
      final result = await _recognizer.processImage(input);
      setState(() {
        _extracted = result.text;
        _processing = false;
      });
      if (_extracted.isEmpty && mounted) {
        PdfFilePicker.showResult(context, 'No text found', isError: true);
      }
    } catch (e) {
      setState(() => _processing = false);
      if (mounted) {
        PdfFilePicker.showResult(context, 'OCR failed: $e', isError: true);
      }
    }
  }

  Future<void> _exportPdf() async {
    if (_extracted.isEmpty) return;
    setState(() => _processing = true);
    try {
      final out = await PdfService.textToPdf(
        _extracted,
        meta: {
          'title': 'OCR Result',
          'name': p.basenameWithoutExtension(_image?.path ?? 'ocr'),
        },
      );
      setState(() => _processing = false);
      if (mounted) {
        PdfFilePicker.showResult(context, 'Saved as PDF');
        await Share.shareXFiles([XFile(out.path)]);
      }
    } catch (e) {
      setState(() => _processing = false);
      if (mounted) {
        PdfFilePicker.showResult(context, 'Export failed: $e', isError: true);
      }
    }
  }

  void _copyText() {
    if (_extracted.isEmpty) return;
    Clipboard.setData(ClipboardData(text: _extracted));
    PdfFilePicker.showResult(context, 'Copied to clipboard');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('OCR – Extract Text'),
        actions: [
          if (_extracted.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.copy),
              onPressed: _copyText,
              tooltip: 'Copy',
            ),
        ],
      ),
      body: Stack(
        children: [
          ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // Info banner
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFB71C1C).withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.redAccent.withOpacity(0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline, color: Colors.redAccent, size: 20),
                    const Gap(10),
                    Expanded(
                      child: Text(
                        'On-device OCR via ML Kit (Latin script). Fully offline after first model load. For PaddleOCR / multi-language add native layer.',
                        style: GoogleFonts.inter(fontSize: 12, color: Colors.white70, height: 1.3),
                      ),
                    ),
                  ],
                ),
              ),
              const Gap(20),
              if (_image == null)
                EmptyState(
                  icon: Icons.document_scanner_outlined,
                  title: 'Select an image',
                  subtitle: 'Pick a photo or scanned document to extract text offline.',
                  actionLabel: 'Choose Image',
                  onAction: _pickImage,
                )
              else ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.file(
                    _image!,
                    height: 200,
                    width: double.infinity,
                    fit: BoxFit.cover,
                  ),
                ),
                const Gap(12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _pickImage,
                        icon: const Icon(Icons.image),
                        label: const Text('Change'),
                      ),
                    ),
                    const Gap(12),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _runOcr,
                        icon: const Icon(Icons.document_scanner),
                        label: const Text('Run OCR'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFC62828),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
              if (_extracted.isNotEmpty) ...[
                const Gap(24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Extracted Text', style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
                    TextButton.icon(
                      onPressed: _exportPdf,
                      icon: const Icon(Icons.picture_as_pdf, size: 18),
                      label: const Text('Export PDF'),
                    ),
                  ],
                ),
                const Gap(8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFF152238),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: SelectableText(
                    _extracted,
                    style: GoogleFonts.inter(fontSize: 14, height: 1.5, color: Colors.white),
                  ),
                ),
              ],
            ],
          ),
          if (_processing) const LoadingOverlay(message: 'Running OCR…'),
        ],
      ),
    );
  }
}
