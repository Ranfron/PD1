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
import 'pp_ocr_model_manager.dart';
import 'pp_ocr.dart';

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
  bool _ppOcrReady = false;

  final TextRecognizer _recognizer =
      TextRecognizer(script: TextRecognitionScript.latin);

  @override
  void initState() {
    super.initState();
    _loadEngine();
  }

  Future<void> _loadEngine() async {
    final e = await OcrEngine.getSelected();
    final ready = await PpOcrModelManager.isReady();
    if (mounted) {
      setState(() {
        _engine = e;
        _ppOcrReady = ready;
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

  Future<String> _runPpOcr(File image) async {
    return PpOcr.processImage(image);
  }

  Future<void> _runOcr() async {
    if (_image == null) return;
    setState(() => _processing = true);
    try {
      String text = '';
      String used = 'ML Kit';

      final wantPp = _engine == OcrEngineType.ppOcr ||
          (_engine == OcrEngineType.auto && _ppOcrReady);

      if (wantPp && _ppOcrReady) {
        text = await _runPpOcr(_image!);
        used = 'PP-OCR (Hindi+English)';
        // Automatic fallback if PP-OCR returns empty
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
                      t == OcrEngineType.ppOcr && !_ppOcrReady;
                  return RadioListTile<OcrEngineType>(
                    value: t,
                    groupValue: _engine,
                    activeColor: const Color(0xFF42A5F5),
                    title: Text(OcrEngine.label(t)),
                    subtitle: Text(
                      disabled
                          ? 'Not installed — download models first'
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
                    label: const Text('Manage PP-OCR Models'),
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
      builder: (ctx) => const _PpOcrModelSheet(),
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
                      _ppOcrReady
                          ? Icons.smart_toy_outlined
                          : Icons.speed,
                      color: const Color(0xFF42A5F5),
                      size: 20,
                    ),
                    const Gap(10),
                    Expanded(
                      child: Text(
                        'Engine: ${OcrEngine.label(_engine)}'
                        '${_ppOcrReady ? ' · PP-OCR ready' : ' · ML Kit only'}',
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

/// Bottom sheet for downloading / deleting PP-OCR models
/// (PP-OCRv6 Medium DET + devanagari_PP-OCRv5_mobile_rec).
class _PpOcrModelSheet extends StatefulWidget {
  const _PpOcrModelSheet();

  @override
  State<_PpOcrModelSheet> createState() => _PpOcrModelSheetState();
}

class _PpOcrModelSheetState extends State<_PpOcrModelSheet> {
  bool _det = false;
  bool _rec = false;
  bool _dict = false;
  double _detProgress = -1;
  double _recProgress = -1;
  double _dictProgress = -1;
  bool _busy = false;
  int _usedBytes = 0;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final det = await PpOcrModelManager.isDetInstalled();
    final rec = await PpOcrModelManager.isRecInstalled();
    final dict = await PpOcrModelManager.isDictInstalled();
    final used = await PpOcrModelManager.usedBytes();
    if (mounted) {
      setState(() {
        _det = det;
        _rec = rec;
        _dict = dict;
        _usedBytes = used;
      });
    }
  }

  String _fmtMb(int bytes) {
    if (bytes <= 0) return '0 MB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  Future<void> _downloadDet() async {
    setState(() {
      _busy = true;
      _detProgress = 0;
    });
    try {
      await PpOcrModelManager.downloadDet(
        onProgress: (p) {
          if (mounted) setState(() => _detProgress = p);
        },
      );
      if (mounted) {
        PdfFilePicker.showResult(context, 'DET model downloaded');
      }
    } catch (e) {
      if (mounted) {
        PdfFilePicker.showResult(
          context,
          'DET download failed: $e\n'
          'You can also place ${PpOcrModelManager.detOnnxName} manually '
          'in Documents/Pdf Power/Models/',
          isError: true,
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _detProgress = -1;
        });
        await _refresh();
      }
    }
  }

  Future<void> _downloadRec() async {
    setState(() {
      _busy = true;
      _recProgress = 0;
    });
    try {
      await PpOcrModelManager.downloadRec(
        onProgress: (p) {
          if (mounted) setState(() => _recProgress = p);
        },
      );
      if (mounted) {
        PdfFilePicker.showResult(context, 'REC model downloaded');
      }
    } catch (e) {
      if (mounted) {
        PdfFilePicker.showResult(
          context,
          'REC download failed: $e\n'
          'Place ${PpOcrModelManager.recOnnxName} manually if needed.',
          isError: true,
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _recProgress = -1;
        });
        await _refresh();
      }
    }
  }

  Future<void> _downloadDict() async {
    setState(() {
      _busy = true;
      _dictProgress = 0;
    });
    try {
      await PpOcrModelManager.downloadDict(
        onProgress: (p) {
          if (mounted) setState(() => _dictProgress = p);
        },
      );
      if (mounted) {
        PdfFilePicker.showResult(context, 'Dictionary downloaded');
      }
    } catch (e) {
      if (mounted) {
        PdfFilePicker.showResult(
          context,
          'Dict download failed: $e',
          isError: true,
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _dictProgress = -1;
        });
        await _refresh();
      }
    }
  }

  Future<void> _downloadAll() async {
    setState(() => _busy = true);
    try {
      await PpOcrModelManager.downloadAll(
        onProgress: (stage, p) {
          if (!mounted) return;
          setState(() {
            if (stage == 'det') _detProgress = p;
            if (stage == 'rec') _recProgress = p;
            if (stage == 'dict') _dictProgress = p;
          });
        },
      );
      if (mounted) {
        PdfFilePicker.showResult(context, 'All PP-OCR models downloaded');
      }
    } catch (e) {
      if (mounted) {
        PdfFilePicker.showResult(context, 'Download failed: $e', isError: true);
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _detProgress = -1;
          _recProgress = -1;
          _dictProgress = -1;
        });
        await _refresh();
      }
    }
  }

  Future<void> _deleteAll() async {
    await PpOcrModelManager.deleteAll();
    await PpOcr.unload();
    await _refresh();
    if (mounted) {
      PdfFilePicker.showResult(context, 'PP-OCR models deleted');
    }
  }

  Widget _modelTile({
    required String title,
    required String subtitle,
    required bool installed,
    required double progress,
    required VoidCallback onDownload,
    required VoidCallback onDelete,
  }) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(title),
      subtitle: Text(
        installed ? 'Installed' : subtitle,
        style: TextStyle(
          fontSize: 12,
          color: installed ? Colors.greenAccent.withOpacity(0.8) : Colors.white54,
        ),
      ),
      trailing: progress >= 0
          ? SizedBox(
              width: 36,
              height: 36,
              child: CircularProgressIndicator(
                value: progress > 0 ? progress : null,
                strokeWidth: 3,
              ),
            )
          : installed
              ? IconButton(
                  icon: const Icon(Icons.delete_outline),
                  onPressed: _busy ? null : onDelete,
                )
              : TextButton(
                  onPressed: _busy ? null : onDownload,
                  child: const Text('Get'),
                ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final allReady = _det && _rec && _dict;
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.65,
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
              'PP-OCR Models',
              style: GoogleFonts.inter(
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
            const Gap(6),
            Text(
              'Pipeline: PP-OCRv6 Medium DET → devanagari_PP-OCRv5_mobile_rec\n'
              'Hindi + English + Numbers · Offline · ~${PpOcrModelManager.detSizeMbApprox + PpOcrModelManager.recSizeMbApprox} MB total\n'
              'Stored in Documents/Pdf Power/Models/',
              style: GoogleFonts.inter(fontSize: 12, color: Colors.white54),
            ),
            const Gap(8),
            Text(
              'Used: ${_fmtMb(_usedBytes)}  ·  Status: ${allReady ? "Ready" : "Incomplete"}',
              style: GoogleFonts.inter(
                fontSize: 12,
                color: allReady ? Colors.greenAccent : Colors.orangeAccent,
              ),
            ),
            const Gap(16),
            _modelTile(
              title: 'Detection · PP-OCRv6 Medium DET',
              subtitle: '${PpOcrModelManager.detOnnxName} · ~${PpOcrModelManager.detSizeMbApprox} MB',
              installed: _det,
              progress: _detProgress,
              onDownload: _downloadDet,
              onDelete: () async {
                final f = File(await PpOcrModelManager.detPath());
                if (await f.exists()) await f.delete();
                await _refresh();
              },
            ),
            const Divider(color: Colors.white12),
            _modelTile(
              title: 'Recognition · Devanagari PP-OCRv5 Mobile',
              subtitle: '${PpOcrModelManager.recOnnxName} · ~${PpOcrModelManager.recSizeMbApprox} MB',
              installed: _rec,
              progress: _recProgress,
              onDownload: _downloadRec,
              onDelete: () async {
                final f = File(await PpOcrModelManager.recPath());
                if (await f.exists()) await f.delete();
                await _refresh();
              },
            ),
            const Divider(color: Colors.white12),
            _modelTile(
              title: 'Dictionary · Devanagari',
              subtitle: PpOcrModelManager.recDictName,
              installed: _dict,
              progress: _dictProgress,
              onDownload: _downloadDict,
              onDelete: () async {
                final f = File(await PpOcrModelManager.dictPath());
                if (await f.exists()) await f.delete();
                await _refresh();
              },
            ),
            const Gap(20),
            if (!allReady)
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _busy ? null : _downloadAll,
                  icon: const Icon(Icons.download),
                  label: const Text('Download All'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1565C0),
                  ),
                ),
              ),
            if (allReady || _det || _rec || _dict) ...[
              const Gap(8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _busy ? null : _deleteAll,
                  icon: const Icon(Icons.delete_forever_outlined),
                  label: const Text('Delete All Models'),
                ),
              ),
            ],
            const Gap(12),
            Text(
              'Note: Official ONNX exports may use different filenames. '
              'Models are ONNX files for the Android ONNX Runtime engine. '
              'You can also place compatible ONNX files manually in the Models folder.',
              style: GoogleFonts.inter(fontSize: 11, color: Colors.white38),
            ),
          ],
        );
      },
    );
  }
}
