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
import 'ocr_engine.dart';
import 'paddle_model_manager.dart';
import 'paddle_vl_ocr.dart';

class OcrPage extends StatefulWidget {
  const OcrPage({super.key});

  @override
  State<OcrPage> createState() => _OcrPageState();
}

class _OcrPageState extends State<OcrPage> {
  File? _image;
  String _extracted = '';
  bool _processing = false;
  String _engineUsed = '';
  OcrEngineType _engine = OcrEngineType.auto;
  bool _paddleReady = false;

  final TextRecognizer _recognizer =
      TextRecognizer(script: TextRecognitionScript.latin);

  @override
  void initState() {
    super.initState();
    _loadEngine();
  }

  Future<void> _loadEngine() async {
    final e = await OcrEngine.getSelected();
    final ready = await PaddleModelManager.isReady();
    if (mounted) {
      setState(() {
        _engine = e;
        _paddleReady = ready;
      });
    }
  }

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
        _engineUsed = '';
      });
    }
  }

  Future<String> _runMlKit(File image) async {
    final input = InputImage.fromFile(image);
    final result = await _recognizer.processImage(input);
    return result.text;
  }

  Future<String> _runPaddle(File image) async {
    return PaddleVlOcr.processImage(image);
  }

  Future<void> _runOcr() async {
    if (_image == null) return;
    setState(() => _processing = true);
    try {
      String text = '';
      String used = 'ML Kit';

      final wantPaddle = _engine == OcrEngineType.paddleVl ||
          (_engine == OcrEngineType.auto && _paddleReady);

      if (wantPaddle && _paddleReady) {
        text = await _runPaddle(_image!);
        used = 'PaddleOCR-VL-1.6';
        // Automatic fallback if Paddle returns empty
        if (text.trim().isEmpty) {
          text = await _runMlKit(_image!);
          used = 'ML Kit (fallback)';
        }
      } else {
        text = await _runMlKit(_image!);
        used = 'ML Kit';
      }

      setState(() {
        _extracted = text;
        _engineUsed = used;
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
          'title': 'OCR Result ($_engineUsed)',
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

  Future<void> _showEngineSheet() async {
    await showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF152238),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const Gap(16),
                Text(
                  'OCR Engine',
                  style: GoogleFonts.inter(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Gap(12),
                ...OcrEngineType.values.map((t) {
                  final disabled =
                      t == OcrEngineType.paddleVl && !_paddleReady;
                  return RadioListTile<OcrEngineType>(
                    value: t,
                    groupValue: _engine,
                    activeColor: const Color(0xFF42A5F5),
                    title: Text(OcrEngine.label(t)),
                    subtitle: Text(
                      disabled
                          ? 'Not installed — download model first'
                          : OcrEngine.subtitle(t),
                      style: TextStyle(
                        fontSize: 12,
                        color: disabled ? Colors.orangeAccent : Colors.white54,
                      ),
                    ),
                    onChanged: disabled
                        ? null
                        : (v) async {
                            if (v == null) return;
                            await OcrEngine.setSelected(v);
                            setState(() => _engine = v);
                            if (ctx.mounted) Navigator.pop(ctx);
                          },
                  );
                }),
                const Gap(8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.pop(ctx);
                      _showModelManager();
                    },
                    icon: const Icon(Icons.download_for_offline_outlined),
                    label: const Text('Manage Paddle Models'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _showModelManager() async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF152238),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) => const _PaddleModelSheet(),
    );
    await _loadEngine();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('OCR – Extract Text'),
        actions: [
          IconButton(
            icon: const Icon(Icons.tune),
            tooltip: 'OCR Engine',
            onPressed: _showEngineSheet,
          ),
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
              // Engine status
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF1565C0).withOpacity(0.15),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: const Color(0xFF42A5F5).withOpacity(0.3),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      _paddleReady
                          ? Icons.smart_toy_outlined
                          : Icons.speed,
                      color: const Color(0xFF42A5F5),
                      size: 20,
                    ),
                    const Gap(10),
                    Expanded(
                      child: Text(
                        'Engine: ${OcrEngine.label(_engine)}'
                        '${_paddleReady ? ' · Paddle ready' : ' · ML Kit only'}',
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          color: Colors.white70,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: _showEngineSheet,
                      child: const Text('Change'),
                    ),
                  ],
                ),
              ),
              const Gap(20),
              if (_image == null)
                EmptyState(
                  icon: Icons.document_scanner_outlined,
                  title: 'Select an image',
                  subtitle:
                      'Pick a photo or scanned document to extract text offline.',
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
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Extracted Text',
                          style: GoogleFonts.inter(fontWeight: FontWeight.w600),
                        ),
                        if (_engineUsed.isNotEmpty)
                          Text(
                            'via $_engineUsed',
                            style: GoogleFonts.inter(
                              fontSize: 11,
                              color: Colors.white38,
                            ),
                          ),
                      ],
                    ),
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
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      height: 1.5,
                      color: Colors.white,
                    ),
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

/// Bottom sheet for downloading / deleting PaddleOCR-VL models.
class _PaddleModelSheet extends StatefulWidget {
  const _PaddleModelSheet();

  @override
  State<_PaddleModelSheet> createState() => _PaddleModelSheetState();
}

class _PaddleModelSheetState extends State<_PaddleModelSheet> {
  PaddleQuant _selected = PaddleQuant.q4Km;
  bool _mmproj = false;
  final Map<PaddleQuant, bool> _installed = {};
  final Map<PaddleQuant, double> _progress = {};
  double _mmProgress = -1;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final sel = await PaddleModelManager.selectedQuant();
    final mm = await PaddleModelManager.isMmprojInstalled();
    final map = <PaddleQuant, bool>{};
    for (final q in PaddleQuant.values) {
      map[q] = await PaddleModelManager.isQuantInstalled(q);
    }
    if (mounted) {
      setState(() {
        _selected = sel;
        _mmproj = mm;
        _installed
          ..clear()
          ..addAll(map);
      });
    }
  }

  Future<void> _downloadQuant(PaddleQuant q) async {
    setState(() {
      _busy = true;
      _progress[q] = 0;
    });
    try {
      await PaddleModelManager.downloadQuant(
        q,
        onProgress: (p) {
          if (mounted) setState(() => _progress[q] = p);
        },
      );
      await PaddleModelManager.setSelectedQuant(q);
      if (mounted) {
        PdfFilePicker.showResult(context, '${q.label} downloaded');
      }
    } catch (e) {
      if (mounted) {
        PdfFilePicker.showResult(
          context,
          'Download failed: $e',
          isError: true,
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _progress.remove(q);
        });
        await _refresh();
      }
    }
  }

  Future<void> _downloadMmproj() async {
    setState(() {
      _busy = true;
      _mmProgress = 0;
    });
    try {
      await PaddleModelManager.downloadMmproj(
        onProgress: (p) {
          if (mounted) setState(() => _mmProgress = p);
        },
      );
      if (mounted) {
        PdfFilePicker.showResult(context, 'mmproj downloaded');
      }
    } catch (e) {
      if (mounted) {
        PdfFilePicker.showResult(context, 'Download failed: $e', isError: true);
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _mmProgress = -1;
        });
        await _refresh();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      maxChildSize: 0.92,
      minChildSize: 0.4,
      builder: (_, controller) {
        return ListView(
          controller: controller,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const Gap(16),
            Text(
              'PaddleOCR-VL-1.6 Models',
              style: GoogleFonts.inter(
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
            const Gap(6),
            Text(
              'Optional advanced OCR (not in APK).\n'
              'Q4+mmproj ≈ 1.1 GB. Stored in Documents/Pdf Power/Models/.',
              style: GoogleFonts.inter(fontSize: 12, color: Colors.white54),
            ),
            const Gap(16),
            // Shared mmproj
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Shared mmproj (~841 MB)'),
              subtitle: Text(_mmproj ? 'Installed' : 'PaddleOCR-VL-1.6-mmproj.gguf · required'),
              trailing: _mmProgress >= 0
                  ? SizedBox(
                      width: 36,
                      height: 36,
                      child: CircularProgressIndicator(
                        value: _mmProgress > 0 ? _mmProgress : null,
                        strokeWidth: 3,
                      ),
                    )
                  : _mmproj
                      ? IconButton(
                          icon: const Icon(Icons.delete_outline),
                          onPressed: _busy
                              ? null
                              : () async {
                                  await PaddleModelManager.deleteMmproj();
                                  await _refresh();
                                },
                        )
                      : TextButton(
                          onPressed: _busy ? null : _downloadMmproj,
                          child: const Text('Download'),
                        ),
            ),
            const Divider(color: Colors.white12),
            ...PaddleQuant.values.map((q) {
              final inst = _installed[q] == true;
              final prog = _progress[q];
              return RadioListTile<PaddleQuant>(
                value: q,
                groupValue: _selected,
                activeColor: const Color(0xFF42A5F5),
                title: Text('${q.label}  ·  ${q.sizeMb} MB'),
                subtitle: Text(inst ? 'Installed' : 'Not installed'),
                secondary: prog != null
                    ? SizedBox(
                        width: 32,
                        height: 32,
                        child: CircularProgressIndicator(
                          value: prog > 0 ? prog : null,
                          strokeWidth: 3,
                        ),
                      )
                    : inst
                        ? IconButton(
                            icon: const Icon(Icons.delete_outline, size: 20),
                            onPressed: _busy
                                ? null
                                : () async {
                                    await PaddleModelManager.deleteQuant(q);
                                    await _refresh();
                                  },
                          )
                        : TextButton(
                            onPressed:
                                _busy ? null : () => _downloadQuant(q),
                            child: const Text('Get'),
                          ),
                onChanged: inst
                    ? (v) async {
                        if (v == null) return;
                        await PaddleModelManager.setSelectedQuant(v);
                        setState(() => _selected = v);
                      }
                    : null,
              );
            }),
          ],
        );
      },
    );
  }
}
