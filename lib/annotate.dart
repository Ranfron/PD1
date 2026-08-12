import 'dart:io';
import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:pdfrx/pdfrx.dart';
import 'file_picker.dart';
import 'tools.dart';

class AnnotatePage extends StatefulWidget {
  const AnnotatePage({super.key});

  @override
  State<AnnotatePage> createState() => _AnnotatePageState();
}

class _AnnotatePageState extends State<AnnotatePage> {
  File? _file;
  Color _penColor = Colors.red;
  double _strokeWidth = 3.0;
  bool _drawing = false;

  final List<Color> _colors = [
    Colors.red,
    Colors.blue,
    Colors.green,
    Colors.orange,
    Colors.purple,
    Colors.yellow,
    Colors.white,
    Colors.black,
  ];

  Future<void> _open() async {
    final files = await PdfFilePicker.pickPdfs();
    if (files.isNotEmpty) {
      setState(() => _file = files.first);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Annotate'),
        actions: [
          IconButton(
            icon: const Icon(Icons.folder_open),
            onPressed: _open,
          ),
        ],
      ),
      body: _file == null
          ? EmptyState(
              icon: Icons.edit_note_rounded,
              title: 'Annotate PDF',
              subtitle: 'Open a PDF to highlight, draw and add notes.\n'
                  'Full annotation saving requires MuPDF annotation API or PDFBox.',
              actionLabel: 'Open PDF',
              onAction: _open,
            )
          : Column(
              children: [
                // Toolbar
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  color: const Color(0xFF152238),
                  child: Row(
                    children: [
                      ..._colors.map((c) => GestureDetector(
                            onTap: () => setState(() => _penColor = c),
                            child: Container(
                              margin: const EdgeInsets.only(right: 8),
                              width: 28,
                              height: 28,
                              decoration: BoxDecoration(
                                color: c,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: _penColor == c ? Colors.white : Colors.transparent,
                                  width: 2.5,
                                ),
                              ),
                            ),
                          )),
                      const Spacer(),
                      IconButton(
                        icon: Icon(
                          _drawing ? Icons.edit : Icons.edit_outlined,
                          color: _drawing ? const Color(0xFF42A5F5) : Colors.white70,
                        ),
                        onPressed: () => setState(() => _drawing = !_drawing),
                        tooltip: 'Toggle draw',
                      ),
                    ],
                  ),
                ),
                // Stroke width
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      const Text('Stroke', style: TextStyle(fontSize: 12, color: Colors.white54)),
                      Expanded(
                        child: Slider(
                          value: _strokeWidth,
                          min: 1,
                          max: 12,
                          activeColor: _penColor,
                          onChanged: (v) => setState(() => _strokeWidth = v),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Stack(
                    children: [
                      PdfViewer.file(
                        _file!.path,
                        params: const PdfViewerParams(
                          backgroundColor: Color(0xFF0A1628),
                        ),
                      ),
                      // Overlay drawing canvas (demo – not persisted to PDF yet)
                      if (_drawing)
                        Positioned.fill(
                          child: _DrawingOverlay(
                            color: _penColor,
                            strokeWidth: _strokeWidth,
                          ),
                        ),
                    ],
                  ),
                ),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  color: const Color(0xFF1A2A40),
                  child: Text(
                    'Drawing overlay is visual only. To permanently save annotations into the PDF, integrate MuPDF annotation layer or PDFBox via native code.',
                    style: GoogleFonts.inter(fontSize: 11, color: Colors.white54, height: 1.3),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),
    );
  }
}

class _DrawingOverlay extends StatefulWidget {
  final Color color;
  final double strokeWidth;

  const _DrawingOverlay({required this.color, required this.strokeWidth});

  @override
  State<_DrawingOverlay> createState() => _DrawingOverlayState();
}

class _DrawingOverlayState extends State<_DrawingOverlay> {
  final List<_Stroke> _strokes = [];
  _Stroke? _current;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onPanStart: (d) {
        _current = _Stroke(color: widget.color, width: widget.strokeWidth)
          ..points.add(d.localPosition);
        setState(() => _strokes.add(_current!));
      },
      onPanUpdate: (d) {
        setState(() => _current?.points.add(d.localPosition));
      },
      onPanEnd: (_) => _current = null,
      child: CustomPaint(
        painter: _StrokePainter(_strokes),
        size: Size.infinite,
      ),
    );
  }
}

class _Stroke {
  final Color color;
  final double width;
  final List<Offset> points = [];

  _Stroke({required this.color, required this.width});
}

class _StrokePainter extends CustomPainter {
  final List<_Stroke> strokes;

  _StrokePainter(this.strokes);

  @override
  void paint(Canvas canvas, Size size) {
    for (final s in strokes) {
      final paint = Paint()
        ..color = s.color
        ..strokeWidth = s.width
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke;
      for (var i = 0; i < s.points.length - 1; i++) {
        canvas.drawLine(s.points[i], s.points[i + 1], paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _StrokePainter old) => true;
}
