import 'dart:io';
import 'dart:ui' as ui;
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
///
/// Every tab shows a live render of the actual page being worked on (via
/// MuPdfService.renderPage), and after each operation the file being edited
/// and the preview both refresh to reflect the *actual result* — previously
/// this screen had no page preview at all (redaction even used a hardcoded
/// sample box), so there was no way to see what you were doing before
/// applying it.
class AdvancedEditPage extends StatefulWidget {
  const AdvancedEditPage({super.key});

  @override
  State<AdvancedEditPage> createState() => _AdvancedEditPageState();
}

class _AdvancedEditPageState extends State<AdvancedEditPage>
    with SingleTickerProviderStateMixin {
  // DPI used for on-screen previews. Kept moderate for fast re-renders after
  // every edit; redaction coordinates are converted back to PDF points using
  // this exact value (see _addRedactionFromRect).
  static const int _previewDpi = 130;

  late TabController _tab;
  File? _file;
  bool _busy = false;
  File? _result;
  String? _textOut;
  Map<String, dynamic>? _info;

  int _currentPage = 1;
  int _pageCount = 1;
  File? _preview;
  ui.Size? _previewPixelSize;
  bool _previewLoading = false;

  // Redaction drag state (Redact tab only).
  Offset? _dragStart;
  Offset? _dragCurrent;
  Rect? _redactRectNorm;
  Size? _previewBoxSize;

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
      _currentPage = 1;
      _pageCount = 1;
      _preview = null;
      _previewPixelSize = null;
      _redactRectNorm = null;
    });
    final info = await MuPdfService.info(_file!.path);
    if (mounted && info != null) {
      setState(() {
        _info = info;
        _pageCount = (info['pageCount'] as num?)?.toInt() ?? 1;
        _titleCtrl.text = '${info['title'] ?? ''}';
        _authorCtrl.text = '${info['author'] ?? ''}';
      });
    }
    await _loadPreview();
  }

  Future<void> _loadPreview() async {
    if (_file == null) return;
    setState(() => _previewLoading = true);
    File? img;
    ui.Size? size;
    try {
      img = await MuPdfService.renderPage(
        _file!,
        page: _currentPage,
        dpi: _previewDpi,
      );
      if (img != null) {
        final bytes = await img.readAsBytes();
        final codec = await ui.instantiateImageCodec(bytes);
        final frame = await codec.getNextFrame();
        size = ui.Size(
          frame.image.width.toDouble(),
          frame.image.height.toDouble(),
        );
        frame.image.dispose();
      }
    } catch (_) {
      img = null;
      size = null;
    }
    if (mounted) {
      setState(() {
        _preview = img;
        _previewPixelSize = size;
        _previewLoading = false;
      });
    }
  }

  void _goToPage(int n) {
    final maxPage = _pageCount < 1 ? 1 : _pageCount;
    final clamped = n < 1 ? 1 : (n > maxPage ? maxPage : n);
    if (clamped == _currentPage) return;
    setState(() {
      _currentPage = clamped;
      _redactRectNorm = null;
    });
    _loadPreview();
  }

  (int, int) _parseRange() {
    final t = _rangeCtrl.text.trim();
    if (t.contains('-')) {
      final parts = t.split('-');
      return (int.tryParse(parts[0]) ?? 1, int.tryParse(parts[1]) ?? 1);
    }
    final n = int.tryParse(t) ?? 1;
    return (n, n);
  }

  /// Runs a MuPDF operation and, on success, refreshes both the file we're
  /// working on (so edits stack) and the on-screen preview (so the result is
  /// actually visible) — not just a "Success" toast with nothing to look at.
  ///
  /// [chain] controls whether `_file` advances to the operation's output.
  /// It's turned off for password-protection, since a later edit couldn't
  /// reopen an encrypted file anyway.
  Future<void> _run(
    Future<File?> Function() op,
    String okMsg, {
    bool chain = true,
  }) async {
    if (_file == null) {
      PdfFilePicker.showResult(context, 'Select a PDF first', isError: true);
      return;
    }
    setState(() => _busy = true);
    try {
      final out = await op();
      if (out == null) {
        if (mounted) {
          setState(() => _busy = false);
          PdfFilePicker.showResult(
            context,
            'Failed (MuPDF unavailable or error)',
            isError: true,
          );
        }
        return;
      }

      setState(() {
        _result = out;
        if (chain) _file = out;
      });

      if (chain) {
        final info = await MuPdfService.info(_file!.path);
        if (info != null && mounted) {
          setState(() {
            _info = info;
            _pageCount = (info['pageCount'] as num?)?.toInt() ?? _pageCount;
            if (_currentPage > _pageCount) _currentPage = _pageCount;
            if (_currentPage < 1) _currentPage = 1;
          });
        }
        await _loadPreview();
      }

      if (mounted) {
        setState(() => _busy = false);
        PdfFilePicker.showResult(context, okMsg);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        PdfFilePicker.showResult(context, '$e', isError: true);
      }
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
        subtitle:
            _info == null ? null : Text('Pages: ${_info!['pageCount'] ?? '?'}'),
        trailing: ElevatedButton(
          onPressed: _pick,
          child: Text(_file == null ? 'Select' : 'Change'),
        ),
      ),
    );
  }

  Widget _pageNavRow() {
    return Row(
      children: [
        IconButton(
          icon: const Icon(Icons.chevron_left),
          onPressed: _currentPage > 1 ? () => _goToPage(_currentPage - 1) : null,
        ),
        Expanded(
          child: Text(
            'Page $_currentPage of $_pageCount',
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.chevron_right),
          onPressed:
              _currentPage < _pageCount ? () => _goToPage(_currentPage + 1) : null,
        ),
      ],
    );
  }

  /// Compact, read-only preview of the current page — used on every tab
  /// except Redact (which needs its own interactive version) so you can
  /// always see the actual page you're about to act on.
  Widget _previewBar() {
    if (_file == null) return const SizedBox.shrink();
    final ratio = (_previewPixelSize != null && _previewPixelSize!.height > 0)
        ? _previewPixelSize!.width / _previewPixelSize!.height
        : 0.75;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.04),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        children: [
          _pageNavRow(),
          const Gap(6),
          AspectRatio(
            aspectRatio: ratio,
            child: _previewLoading
                ? const Center(
                    child: CircularProgressIndicator(strokeWidth: 2))
                : _preview != null
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: Image.file(_preview!, fit: BoxFit.contain),
                      )
                    : Container(
                        color: Colors.black26,
                        alignment: Alignment.center,
                        child: Text(
                          'Preview unavailable',
                          style:
                              GoogleFonts.inter(color: Colors.white38, fontSize: 12),
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _rectOverlay(Rect r, {Color color = Colors.amber}) {
    return Positioned(
      left: r.left,
      top: r.top,
      width: r.width,
      height: r.height,
      child: IgnorePointer(
        child: Container(
          decoration: BoxDecoration(
            color: color.withOpacity(0.25),
            border: Border.all(color: color, width: 2),
          ),
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
              onPressed: () => Share.shareXFiles([XFile(_result!.path)]),
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
        _previewBar(),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextField(
                controller: _rangeCtrl,
                decoration: const InputDecoration(
                  labelText: 'Page range (e.g. 1-3)',
                  filled: true,
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            const Gap(8),
            OutlinedButton(
              onPressed: _file == null
                  ? null
                  : () => setState(
                      () => _rangeCtrl.text = '$_currentPage-$_currentPage'),
              child: const Text('This page'),
            ),
          ],
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
        _previewBar(),
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
              // Don't chain: further MuPDF edits can't reopen an encrypted
              // file without a password prompt this screen doesn't have.
              chain: false,
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
        _previewBar(),
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
        _previewBar(),
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

  Future<void> _addRedactionFromRect() async {
    final rectNorm = _redactRectNorm;
    final pxSize = _previewPixelSize;
    final boxSize = _previewBoxSize;
    if (rectNorm == null ||
        pxSize == null ||
        boxSize == null ||
        boxSize.width <= 0 ||
        boxSize.height <= 0 ||
        _file == null) {
      return;
    }

    // The rectangle was drawn in the on-screen box's local coordinates;
    // convert to the true rendered PNG's pixel coordinates first.
    final sx = pxSize.width / boxSize.width;
    final sy = pxSize.height / boxSize.height;
    final pxLeft = rectNorm.left * sx;
    final pxTop = rectNorm.top * sy;
    final pxRight = rectNorm.right * sx;
    final pxBottom = rectNorm.bottom * sy;

    // The preview was rendered at _previewDpi with no rotation/flip, so
    // pixel -> PDF-point conversion is a single linear scale (same
    // convention pdf_edit_engine.dart already uses for ML Kit boxes).
    final scale = _previewDpi / 72.0;

    await _run(
      () => MuPdfService.addRedaction(
        _file!,
        page: _currentPage,
        x0: pxLeft / scale,
        y0: pxTop / scale,
        x1: pxRight / scale,
        y1: pxBottom / scale,
      ),
      'Redaction marked — tap Apply to permanently remove it',
    );
    if (mounted) setState(() => _redactRectNorm = null);
  }

  Widget _redactTab() {
    final ratio = (_previewPixelSize != null && _previewPixelSize!.height > 0)
        ? _previewPixelSize!.width / _previewPixelSize!.height
        : 0.75;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'Drag on the page below to mark the area to redact, then tap '
          '"Add redaction here". Nothing is removed until you tap Apply.',
          style: GoogleFonts.inter(fontSize: 13, color: Colors.white60),
        ),
        const Gap(12),
        if (_file != null) ...[
          _pageNavRow(),
          const Gap(8),
          AspectRatio(
            aspectRatio: ratio,
            child: _previewLoading
                ? const Center(
                    child: CircularProgressIndicator(strokeWidth: 2))
                : _preview == null
                    ? Container(
                        color: Colors.black26,
                        alignment: Alignment.center,
                        child: Text(
                          'Preview unavailable',
                          style: GoogleFonts.inter(
                              color: Colors.white38, fontSize: 12),
                        ),
                      )
                    : LayoutBuilder(
                        builder: (context, constraints) {
                          final box =
                              Size(constraints.maxWidth, constraints.maxHeight);
                          _previewBoxSize = box;
                          return GestureDetector(
                            onPanStart: (d) => setState(() {
                              _dragStart = d.localPosition;
                              _dragCurrent = d.localPosition;
                            }),
                            onPanUpdate: (d) => setState(() {
                              _dragCurrent = d.localPosition;
                            }),
                            onPanEnd: (_) => setState(() {
                              if (_dragStart != null && _dragCurrent != null) {
                                final r = Rect.fromPoints(
                                        _dragStart!, _dragCurrent!)
                                    .intersect(Offset.zero & box);
                                if (r.width > 4 && r.height > 4) {
                                  _redactRectNorm = r;
                                }
                              }
                              _dragStart = null;
                              _dragCurrent = null;
                            }),
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(6),
                                  child:
                                      Image.file(_preview!, fit: BoxFit.fill),
                                ),
                                if (_dragStart != null && _dragCurrent != null)
                                  _rectOverlay(
                                      Rect.fromPoints(_dragStart!, _dragCurrent!)),
                                if (_dragStart == null &&
                                    _redactRectNorm != null)
                                  _rectOverlay(_redactRectNorm!,
                                      color: Colors.redAccent),
                              ],
                            ),
                          );
                        },
                      ),
          ),
        ],
        const Gap(12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ElevatedButton(
              onPressed: _redactRectNorm == null ? null : _addRedactionFromRect,
              child: const Text('Add redaction here'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red[900]),
              onPressed: _file == null
                  ? null
                  : () => _run(
                        () => MuPdfService.applyRedactions(_file!),
                        'Redactions applied — content permanently removed',
                      ),
              child: const Text('Apply redactions (permanent)'),
            ),
          ],
        ),
        _resultCard(),
      ],
    );
  }

  Widget _textTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _previewBar(),
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
