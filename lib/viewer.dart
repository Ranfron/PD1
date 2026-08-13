import 'dart:io';
import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:share_plus/share_plus.dart';
import 'package:open_filex/open_filex.dart';
import 'file_picker.dart';
import 'tools.dart';
import 'pdf_edit_engine.dart';

class ViewerPage extends StatefulWidget {
  const ViewerPage({super.key});

  @override
  State<ViewerPage> createState() => _ViewerPageState();
}

class _ViewerPageState extends State<ViewerPage> {
  File? _file;
  bool _loading = false;
  bool _editMode = false;
  int _page = 1;
  PdfRegionObject? _selected;
  final _engine = PdfEditEngine();
  final _textCtrl = TextEditingController();
  Offset? _dragStart;
  Offset? _dragEnd;
  PageCoordMapper? _mapper;
  String _analysisSource = '';

  Future<void> _pickAndOpen() async {
    setState(() => _loading = true);
    try {
      final files = await PdfFilePicker.pickPdfs();
      if (files.isEmpty) {
        setState(() => _loading = false);
        return;
      }
      final file = files.first;
      _engine.open(file);
      setState(() {
        _file = file;
        _selected = null;
        _loading = false;
        _analysisSource = '';
      });
      await _engine.analyzePage(1);
      final c = _engine.cached(1);
      if (c != null && mounted) {
        setState(() => _analysisSource = c.source);
      }
    } catch (e) {
      setState(() => _loading = false);
      if (mounted) {
        PdfFilePicker.showResult(context, 'Failed to open: $e', isError: true);
      }
    }
  }

  void _updateMapper(BoxConstraints box) {
    final a = _engine.cached(_page);
    final pw = a?.width ?? _engine.defaultPageWidth;
    final ph = a?.height ?? _engine.defaultPageHeight;
    _mapper = PageCoordMapper(
      pageWidth: pw,
      pageHeight: ph,
      viewWidth: box.maxWidth,
      viewHeight: box.maxHeight,
    );
  }

  Future<void> _handleSelect(
    Offset local,
    BoxConstraints box, {
    SelectLevel level = SelectLevel.word,
  }) async {
    if (!_editMode || _file == null) return;
    _updateMapper(box);
    final m = _mapper!;
    final (px, py) = m.toPage(local.dx, local.dy);
    setState(() => _loading = true);
    try {
      final obj = await _engine.selectAt(_page, px, py, prefer: level);
      setState(() {
        _selected = obj;
        _textCtrl.text = obj?.text ?? '';
        _loading = false;
        _analysisSource = _engine.cached(_page)?.source ?? '';
      });
      if (obj != null && mounted) {
        await _showEditSheet(obj);
      } else if (mounted) {
        PdfFilePicker.showResult(
          context,
          'No object · source: $_analysisSource',
        );
      }
    } catch (e) {
      setState(() => _loading = false);
    }
  }

  Future<void> _showEditSheet(PdfRegionObject obj) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF152238),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.fromLTRB(
              16, 16, 16, 28 + MediaQuery.of(ctx).viewInsets.bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${obj.level.name.toUpperCase()} · ${obj.type.name}',
                style: GoogleFonts.inter(fontWeight: FontWeight.w600),
              ),
              Text(
                'Analysis: $_analysisSource · conf ${(obj.confidence * 100).toStringAsFixed(0)}%',
                style: GoogleFonts.inter(fontSize: 11, color: Colors.white38),
              ),
              const Gap(8),
              if (obj.text.isNotEmpty)
                Text(
                  obj.text.length > 240
                      ? '${obj.text.substring(0, 240)}…'
                      : obj.text,
                  style: GoogleFonts.inter(fontSize: 13, color: Colors.white70),
                  maxLines: 5,
                ),
              const Gap(12),
              TextField(
                controller: _textCtrl,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Replace (local patch)',
                  filled: true,
                  border: OutlineInputBorder(),
                ),
              ),
              const Gap(12),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () async {
                        Navigator.pop(ctx);
                        setState(() => _loading = true);
                        final out = await _engine.replaceText(
                          obj,
                          _textCtrl.text,
                          page: _page,
                        );
                        setState(() {
                          _loading = false;
                          if (out != null) _file = out;
                        });
                        if (out != null && mounted) {
                          PdfFilePicker.showResult(
                              context, 'Local text patch applied');
                        }
                      },
                      child: const Text('Replace'),
                    ),
                  ),
                  const Gap(8),
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red[800]),
                      onPressed: () async {
                        Navigator.pop(ctx);
                        setState(() => _loading = true);
                        final out = await _engine.removeRegion(_page, obj);
                        setState(() {
                          _loading = false;
                          if (out != null) _file = out;
                        });
                        if (out != null && mounted) {
                          PdfFilePicker.showResult(context, 'Region redacted');
                        }
                      },
                      child: const Text('Remove'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    _textCtrl.dispose();
    _engine.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
            _file != null ? _file!.path.split('/').last : 'PDF Viewer'),
        actions: [
          if (_file != null) ...[
            IconButton(
              tooltip: 'Undo',
              icon: const Icon(Icons.undo),
              onPressed: _engine.canUndo
                  ? () {
                      final f = _engine.undo();
                      if (f != null) setState(() => _file = f);
                    }
                  : null,
            ),
            IconButton(
              tooltip: 'Redo',
              icon: const Icon(Icons.redo),
              onPressed: _engine.canRedo
                  ? () {
                      final f = _engine.redo();
                      if (f != null) setState(() => _file = f);
                    }
                  : null,
            ),
            IconButton(
              tooltip: _editMode ? 'View mode' : 'Edit mode',
              icon: Icon(
                _editMode ? Icons.edit_off : Icons.touch_app,
                color: _editMode ? const Color(0xFF42A5F5) : null,
              ),
              onPressed: () => setState(() => _editMode = !_editMode),
            ),
            IconButton(
              icon: const Icon(Icons.share_rounded),
              onPressed: () => SharePlus.instance.share(ShareParams(files: [XFile(_file!.path)])),
            ),
            IconButton(
              icon: const Icon(Icons.open_in_new_rounded),
              onPressed: () => OpenFilex.open(_file!.path),
            ),
          ],
          IconButton(
            icon: const Icon(Icons.folder_open_rounded),
            onPressed: _pickAndOpen,
          ),
        ],
      ),
      body: Stack(
        children: [
          if (_file == null)
            EmptyState(
              icon: Icons.picture_as_pdf_outlined,
              title: 'No PDF opened',
              subtitle:
                  'Open PDF → Edit mode.\nTap = word · Long-press = line · Drag = region',
              actionLabel: 'Open PDF',
              onAction: _pickAndOpen,
            )
          else
            Column(
              children: [
                if (_editMode)
                  Container(
                    width: double.infinity,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    color: const Color(0xFF1565C0).withOpacity(0.25),
                    child: Text(
                      'Edit · tap word · long-press line · drag region'
                      '${_analysisSource.isNotEmpty ? ' · $_analysisSource' : ''}',
                      style: GoogleFonts.inter(
                          fontSize: 12, color: Colors.white70),
                    ),
                  ),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      return GestureDetector(
                        onTapDown: _editMode
                            ? (d) => _handleSelect(
                                  d.localPosition,
                                  constraints,
                                  level: SelectLevel.word,
                                )
                            : null,
                        onLongPressStart: _editMode
                            ? (d) => _handleSelect(
                                  d.localPosition,
                                  constraints,
                                  level: SelectLevel.line,
                                )
                            : null,
                        onPanStart: _editMode
                            ? (d) => setState(() {
                                  _dragStart = d.localPosition;
                                  _dragEnd = d.localPosition;
                                })
                            : null,
                        onPanUpdate: _editMode
                            ? (d) =>
                                setState(() => _dragEnd = d.localPosition)
                            : null,
                        onPanEnd: _editMode
                            ? (_) async {
                                if (_dragStart == null || _dragEnd == null) {
                                  return;
                                }
                                _updateMapper(constraints);
                                final m = _mapper!;
                                final (x0, y0) =
                                    m.toPage(_dragStart!.dx, _dragStart!.dy);
                                final (x1, y1) =
                                    m.toPage(_dragEnd!.dx, _dragEnd!.dy);
                                final list = await _engine.selectRegion(
                                  _page,
                                  x0,
                                  y0,
                                  x1,
                                  y1,
                                );
                                setState(() {
                                  _dragStart = null;
                                  _dragEnd = null;
                                  _selected =
                                      list.isNotEmpty ? list.first : null;
                                });
                                if (_selected != null) {
                                  _textCtrl.text = _selected!.text;
                                  await _showEditSheet(_selected!);
                                }
                              }
                            : null,
                        child: Stack(
                          children: [
                            PdfViewer.file(
                              _file!.path,
                              params: PdfViewerParams(
                                backgroundColor: const Color(0xFF0A1628),
                                loadingBannerBuilder:
                                    (context, bytesDownloaded, totalBytes) {
                                  return const Center(
                                    child: CircularProgressIndicator(
                                        color: Color(0xFF42A5F5)),
                                  );
                                },
                              ),
                            ),
                            if (_editMode &&
                                _dragStart != null &&
                                _dragEnd != null)
                              Positioned.fill(
                                child: CustomPaint(
                                  painter:
                                      _RectPainter(_dragStart!, _dragEnd!),
                                ),
                              ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          if (_loading) const LoadingOverlay(message: 'Working…'),
        ],
      ),
      floatingActionButton: _file == null
          ? FloatingActionButton.extended(
              onPressed: _pickAndOpen,
              icon: const Icon(Icons.folder_open),
              label: const Text('Open PDF'),
              backgroundColor: const Color(0xFF1565C0),
            )
          : null,
    );
  }
}

class _RectPainter extends CustomPainter {
  final Offset a, b;
  _RectPainter(this.a, this.b);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF42A5F5).withOpacity(0.35)
      ..style = PaintingStyle.fill;
    final border = Paint()
      ..color = const Color(0xFF42A5F5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    final rect = Rect.fromPoints(a, b);
    canvas.drawRect(rect, paint);
    canvas.drawRect(rect, border);
  }

  @override
  bool shouldRepaint(covariant _RectPainter old) => true;
}
