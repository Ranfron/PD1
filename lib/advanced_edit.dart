import 'dart:io';
import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';
import 'file_picker.dart';
import 'mupdf_service.dart';
import 'tools.dart';

/// Single screen for advanced MuPDF edits: protect, watermark, metadata,
/// pages (rotate/delete/blank), redact, flatten, extract text.
class AdvancedEditPage extends StatefulWidget {
  const AdvancedEditPage({super.key});

  @override
  State<AdvancedEditPage> createState() => _AdvancedEditPageState();
}

class _AdvancedEditPageState extends State<AdvancedEditPage>
    with SingleTickerProviderStateMixin {
  late TabController _tab;
  File? _file;
  bool _busy = false;
  File? _result;
  String? _textOut;
  Map<String, dynamic>? _info;

  final _passCtrl = TextEditingController();
  final _wmCtrl = TextEditingController(text: 'CONFIDENTIAL');
  final _titleCtrl = TextEditingController();
  final _authorCtrl = TextEditingController();
  final _rangeCtrl = TextEditingController(text: '1-1');
  int _degrees = 90;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 6, vsync: this);
  }

  @override
  void dispose() {
    _tab.dispose();
    _passCtrl.dispose();
    _wmCtrl.dispose();
    _titleCtrl.dispose();
    _authorCtrl.dispose();
    _rangeCtrl.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    final files = await PdfFilePicker.pickPdfs();
    if (files.isEmpty) return;
    setState(() {
      _file = files.first;
      _result = null;
      _textOut = null;
      _info = null;
    });
    final info = await MuPdfService.info(_file!.path);
    if (mounted && info != null) {
      setState(() {
        _info = info;
        _titleCtrl.text = '${info['title'] ?? ''}';
        _authorCtrl.text = '${info['author'] ?? ''}';
      });
    }
  }

  (int, int) _parseRange() {
    final t = _rangeCtrl.text.trim();
    if (t.contains('-')) {
      final p = t.split('-');
      return (int.tryParse(p[0]) ?? 1, int.tryParse(p[1]) ?? 1);
    }
    final n = int.tryParse(t) ?? 1;
    return (n, n);
  }

  Future<void> _run(Future<File?> Function() op, String okMsg) async {
    if (_file == null) {
      PdfFilePicker.showResult(context, 'Select a PDF first', isError: true);
      return;
    }
    setState(() => _busy = true);
    try {
      final out = await op();
      setState(() {
        _result = out;
        _busy = false;
      });
      if (out != null) {
        PdfFilePicker.showResult(context, okMsg);
      } else {
        PdfFilePicker.showResult(
            context, 'Failed (MuPDF unavailable or error)',
            isError: true);
      }
    } catch (e) {
      setState(() => _busy = false);
      PdfFilePicker.showResult(context, '$e', isError: true);
    }
  }

  Widget _fileCard() {
    return Card(
      child: ListTile(
        leading: const Icon(Icons.picture_as_pdf, color: Color(0xFF42A5F5)),
        title: Text(
          _file == null ? 'No PDF selected' : p.basename(_file!.path),
          style: GoogleFonts.inter(fontWeight: FontWeight.w500),
        ),
        subtitle: _info == null
            ? null
            : Text('Pages: ${_info!['pageCount'] ?? '?'}'),
        trailing: ElevatedButton(
          onPressed: _pick,
          child: Text(_file == null ? 'Select' : 'Change'),
        ),
      ),
    );
  }

  Widget _resultCard() {
    if (_result == null && (_textOut == null || _textOut!.isEmpty)) {
      return const SizedBox.shrink();
    }
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1B5E20).withOpacity(0.25),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.greenAccent.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_result != null) ...[
            Text(p.basename(_result!.path),
                style: GoogleFonts.inter(fontSize: 13)),
            const Gap(8),
            ElevatedButton.icon(
              onPressed: () => SharePlus.instance.share(ShareParams(files: [XFile(_result!.path)])),
              icon: const Icon(Icons.share, size: 18),
              label: const Text('Share'),
            ),
          ],
          if (_textOut != null && _textOut!.isNotEmpty) ...[
            Text('Extracted text',
                style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
            const Gap(6),
            SelectableText(_textOut!,
                style: GoogleFonts.inter(fontSize: 13, height: 1.4)),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Advanced Edit'),
        bottom: TabBar(
          controller: _tab,
          isScrollable: true,
          tabs: const [
            Tab(text: 'Pages'),
            Tab(text: 'Protect'),
            Tab(text: 'Watermark'),
            Tab(text: 'Metadata'),
            Tab(text: 'Redact'),
            Tab(text: 'Text'),
          ],
        ),
      ),
      body: Stack(
        children: [
          Column(
            children: [
              Padding(padding: const EdgeInsets.all(12), child: _fileCard()),
              Expanded(
                child: TabBarView(
                  controller: _tab,
                  children: [
                    _pagesTab(),
                    _protectTab(),
                    _watermarkTab(),
                    _metaTab(),
                    _redactTab(),
                    _textTab(),
                  ],
                ),
              ),
            ],
          ),
          if (_busy) const LoadingOverlay(message: 'Processing with MuPDF…'),
        ],
      ),
    );
  }

  Widget _pagesTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        TextField(
          controller: _rangeCtrl,
          decoration: const InputDecoration(
            labelText: 'Page range (e.g. 1-3)',
            filled: true,
            border: OutlineInputBorder(),
          ),
        ),
        const Gap(12),
        Row(
          children: [
            const Text('Rotate'),
            const Gap(12),
            DropdownButton<int>(
              value: _degrees,
              items: const [
                DropdownMenuItem(value: 90, child: Text('90°')),
                DropdownMenuItem(value: 180, child: Text('180°')),
                DropdownMenuItem(value: 270, child: Text('270°')),
              ],
              onChanged: (v) => setState(() => _degrees = v ?? 90),
            ),
          ],
        ),
        const Gap(12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ElevatedButton(
              onPressed: () {
                final (s, e) = _parseRange();
                _run(
                  () => MuPdfService.rotatePages(_file!,
                      start: s, end: e, degrees: _degrees),
                  'Rotated',
                );
              },
              child: const Text('Rotate'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red[800]),
              onPressed: () {
                final (s, e) = _parseRange();
                _run(
                  () => MuPdfService.deletePages(_file!, start: s, end: e),
                  'Pages deleted',
                );
              },
              child: const Text('Delete pages'),
            ),
            ElevatedButton(
              onPressed: () => _run(
                () => MuPdfService.addBlankPage(_file!),
                'Blank page added',
              ),
              child: const Text('Add blank'),
            ),
            ElevatedButton(
              onPressed: () => _run(
                () => MuPdfService.flatten(_file!),
                'Flattened',
              ),
              child: const Text('Flatten'),
            ),
          ],
        ),
        _resultCard(),
      ],
    );
  }

  Widget _protectTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        TextField(
          controller: _passCtrl,
          obscureText: true,
          decoration: const InputDecoration(
            labelText: 'Password (AES-256)',
            filled: true,
            border: OutlineInputBorder(),
          ),
        ),
        const Gap(16),
        ElevatedButton.icon(
          onPressed: () {
            if (_passCtrl.text.isEmpty) {
              PdfFilePicker.showResult(context, 'Enter password',
                  isError: true);
              return;
            }
            _run(
              () => MuPdfService.encrypt(_file!,
                  userPassword: _passCtrl.text),
              'Encrypted',
            );
          },
          icon: const Icon(Icons.lock),
          label: const Text('Lock PDF'),
        ),
        _resultCard(),
      ],
    );
  }

  Widget _watermarkTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        TextField(
          controller: _wmCtrl,
          decoration: const InputDecoration(
            labelText: 'Watermark text',
            filled: true,
            border: OutlineInputBorder(),
          ),
        ),
        const Gap(16),
        ElevatedButton.icon(
          onPressed: () => _run(
            () => MuPdfService.watermarkText(_file!, text: _wmCtrl.text),
            'Watermark applied',
          ),
          icon: const Icon(Icons.branding_watermark),
          label: const Text('Apply watermark'),
        ),
        _resultCard(),
      ],
    );
  }

  Widget _metaTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        TextField(
          controller: _titleCtrl,
          decoration: const InputDecoration(
            labelText: 'Title',
            filled: true,
            border: OutlineInputBorder(),
          ),
        ),
        const Gap(10),
        TextField(
          controller: _authorCtrl,
          decoration: const InputDecoration(
            labelText: 'Author',
            filled: true,
            border: OutlineInputBorder(),
          ),
        ),
        const Gap(16),
        ElevatedButton.icon(
          onPressed: () => _run(
            () => MuPdfService.setMetadata(_file!, {
              'title': _titleCtrl.text,
              'author': _authorCtrl.text,
            }),
            'Metadata saved',
          ),
          icon: const Icon(Icons.info_outline),
          label: const Text('Save metadata'),
        ),
        _resultCard(),
      ],
    );
  }

  Widget _redactTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'Add a redaction box on page 1 (sample area), then Apply to permanently remove content under the box.',
          style: GoogleFonts.inter(fontSize: 13, color: Colors.white60),
        ),
        const Gap(16),
        ElevatedButton(
          onPressed: () => _run(
            () => MuPdfService.addRedaction(
              _file!,
              page: 1,
              x0: 50,
              y0: 50,
              x1: 300,
              y1: 120,
            ),
            'Redaction mark added',
          ),
          child: const Text('Add sample redaction (page 1)'),
        ),
        const Gap(8),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: Colors.red[900]),
          onPressed: () => _run(
            () => MuPdfService.applyRedactions(_file!),
            'Redactions applied',
          ),
          child: const Text('Apply redactions (permanent)'),
        ),
        _resultCard(),
      ],
    );
  }

  Widget _textTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        ElevatedButton.icon(
          onPressed: () async {
            if (_file == null) return;
            setState(() => _busy = true);
            final t = await MuPdfService.extractText(_file!);
            setState(() {
              _textOut = t ?? '';
              _busy = false;
            });
            if ((t ?? '').isEmpty) {
              PdfFilePicker.showResult(context, 'No text / failed',
                  isError: true);
            }
          },
          icon: const Icon(Icons.text_snippet),
          label: const Text('Extract all text (MuPDF)'),
        ),
        _resultCard(),
      ],
    );
  }
}
