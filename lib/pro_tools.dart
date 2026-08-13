import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:gap/gap.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'file_picker.dart';
import 'mupdf_service.dart';
import 'tools.dart';

/// Interactive text, image insert, form fields, and drawn signature.
class ProToolsPage extends StatefulWidget {
  const ProToolsPage({super.key});

  @override
  State<ProToolsPage> createState() => _ProToolsPageState();
}

class _ProToolsPageState extends State<ProToolsPage>
    with SingleTickerProviderStateMixin {
  late TabController _tab;
  File? _pdf;
  File? _image;
  File? _result;
  bool _busy = false;

  final _textCtrl = TextEditingController(text: 'Sample text');
  final _fieldNameCtrl = TextEditingController(text: 'name');
  final _fieldValCtrl = TextEditingController();
  final _pageCtrl = TextEditingController(text: '1');
  final _sigKey = GlobalKey();
  final List<Offset?> _sigPoints = [];

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tab.dispose();
    _textCtrl.dispose();
    _fieldNameCtrl.dispose();
    _fieldValCtrl.dispose();
    _pageCtrl.dispose();
    super.dispose();
  }

  int get _page => int.tryParse(_pageCtrl.text) ?? 1;

  Future<void> _pickPdf() async {
    final f = await PdfFilePicker.pickPdfs();
    if (f.isNotEmpty) setState(() { _pdf = f.first; _result = null; });
  }

  Future<void> _pickImage() async {
    final f = await PdfFilePicker.pickImages(allowMultiple: false);
    if (f.isNotEmpty) setState(() => _image = f.first);
  }

  Future<void> _run(Future<File?> Function() op, String msg) async {
    if (_pdf == null) {
      PdfFilePicker.showResult(context, 'Select PDF first', isError: true);
      return;
    }
    setState(() => _busy = true);
    try {
      final out = await op();
      setState(() { _result = out; _busy = false; });
      PdfFilePicker.showResult(
        context,
        out != null ? msg : 'Failed — MuPDF error or unavailable',
        isError: out == null,
      );
    } catch (e) {
      setState(() => _busy = false);
      PdfFilePicker.showResult(context, '$e', isError: true);
    }
  }

  Future<File?> _exportSignaturePng() async {
    final boundary =
        _sigKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null) return null;
    final img = await boundary.toImage(pixelRatio: 2);
    final data = await img.toByteData(format: ui.ImageByteFormat.png);
    if (data == null) return null;
    final dir = await getTemporaryDirectory();
    final f = File(p.join(dir.path, 'sig_${DateTime.now().millisecondsSinceEpoch}.png'));
    await f.writeAsBytes(data.buffer.asUint8List());
    return f;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pro Tools'),
        bottom: TabBar(
          controller: _tab,
          isScrollable: true,
          tabs: const [
            Tab(text: 'Text'),
            Tab(text: 'Image'),
            Tab(text: 'Forms'),
            Tab(text: 'Sign'),
          ],
        ),
      ),
      body: Stack(
        children: [
          Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: Card(
                  child: ListTile(
                    leading: const Icon(Icons.picture_as_pdf),
                    title: Text(_pdf == null
                        ? 'No PDF'
                        : p.basename(_pdf!.path)),
                    trailing: ElevatedButton(
                      onPressed: _pickPdf,
                      child: Text(_pdf == null ? 'Select' : 'Change'),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: TextField(
                  controller: _pageCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Target page',
                    filled: true,
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ),
              Expanded(
                child: TabBarView(
                  controller: _tab,
                  children: [
                    _textTab(),
                    _imageTab(),
                    _formsTab(),
                    _signTab(),
                  ],
                ),
              ),
              if (_result != null)
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(p.basename(_result!.path),
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                      ),
                      IconButton(
                        icon: const Icon(Icons.share),
                        onPressed: () =>
                            SharePlus.instance.share(ShareParams(files: [XFile(_result!.path)])),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          if (_busy) const LoadingOverlay(message: 'Applying…'),
        ],
      ),
    );
  }

  Widget _textTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        TextField(
          controller: _textCtrl,
          maxLines: 3,
          decoration: const InputDecoration(
            labelText: 'Text to insert',
            filled: true,
            border: OutlineInputBorder(),
          ),
        ),
        const Gap(12),
        Text(
          'Adds a FreeText annotation box on the page (interactive text layer).',
          style: GoogleFonts.inter(fontSize: 12, color: Colors.white54),
        ),
        const Gap(16),
        ElevatedButton.icon(
          onPressed: () => _run(
            () => MuPdfService.addFreeText(
              _pdf!,
              page: _page,
              text: _textCtrl.text,
            ),
            'Text added',
          ),
          icon: const Icon(Icons.text_fields),
          label: const Text('Insert text'),
        ),
      ],
    );
  }

  Widget _imageTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (_image != null)
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.file(_image!, height: 120, fit: BoxFit.contain),
          ),
        const Gap(8),
        OutlinedButton.icon(
          onPressed: _pickImage,
          icon: const Icon(Icons.image),
          label: Text(_image == null ? 'Pick image' : 'Change image'),
        ),
        const Gap(16),
        ElevatedButton.icon(
          onPressed: _image == null
              ? null
              : () => _run(
                    () => MuPdfService.addStampImage(
                      _pdf!,
                      image: _image!,
                      page: _page,
                    ),
                    'Image stamped',
                  ),
          icon: const Icon(Icons.add_photo_alternate),
          label: const Text('Insert image stamp'),
        ),
      ],
    );
  }

  Widget _formsTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        TextField(
          controller: _fieldNameCtrl,
          decoration: const InputDecoration(
            labelText: 'Field name',
            filled: true,
            border: OutlineInputBorder(),
          ),
        ),
        const Gap(10),
        TextField(
          controller: _fieldValCtrl,
          decoration: const InputDecoration(
            labelText: 'Default value',
            filled: true,
            border: OutlineInputBorder(),
          ),
        ),
        const Gap(8),
        Text(
          'Creates a text form field (AcroForm widget when supported).',
          style: GoogleFonts.inter(fontSize: 12, color: Colors.white54),
        ),
        const Gap(16),
        ElevatedButton.icon(
          onPressed: () => _run(
            () => MuPdfService.addTextField(
              _pdf!,
              page: _page,
              name: _fieldNameCtrl.text,
              value: _fieldValCtrl.text,
            ),
            'Form field added',
          ),
          icon: const Icon(Icons.input),
          label: const Text('Add text field'),
        ),
      ],
    );
  }

  Widget _signTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Draw signature',
            style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
        const Gap(8),
        Container(
          height: 180,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white24),
          ),
          child: RepaintBoundary(
            key: _sigKey,
            child: GestureDetector(
              onPanStart: (d) =>
                  setState(() => _sigPoints.add(d.localPosition)),
              onPanUpdate: (d) =>
                  setState(() => _sigPoints.add(d.localPosition)),
              onPanEnd: (_) => setState(() => _sigPoints.add(null)),
              child: CustomPaint(
                painter: _SigPainter(_sigPoints),
                size: Size.infinite,
              ),
            ),
          ),
        ),
        const Gap(8),
        Row(
          children: [
            TextButton(
              onPressed: () => setState(() => _sigPoints.clear()),
              child: const Text('Clear'),
            ),
            const Spacer(),
            ElevatedButton.icon(
              onPressed: () async {
                if (_pdf == null) {
                  PdfFilePicker.showResult(context, 'Select PDF first',
                      isError: true);
                  return;
                }
                setState(() => _busy = true);
                try {
                  final png = await _exportSignaturePng();
                  if (png == null) throw Exception('Signature empty');
                  final out = await MuPdfService.addStampImage(
                    _pdf!,
                    image: png,
                    page: _page,
                    x0: 80,
                    y0: 80,
                    x1: 280,
                    y1: 160,
                  );
                  setState(() {
                    _result = out;
                    _busy = false;
                  });
                  PdfFilePicker.showResult(
                    context,
                    out != null
                        ? 'Signature stamped'
                        : 'Stamp failed',
                    isError: out == null,
                  );
                } catch (e) {
                  setState(() => _busy = false);
                  PdfFilePicker.showResult(context, '$e', isError: true);
                }
              },
              icon: const Icon(Icons.draw),
              label: const Text('Stamp signature'),
            ),
          ],
        ),
        const Gap(12),
        Text(
          'Drawn signature is saved as image stamp on the PDF. '
          'Certificate-based (PKCS#12) signing can be added with a keystore later.',
          style: GoogleFonts.inter(fontSize: 11, color: Colors.white38),
        ),
      ],
    );
  }
}

class _SigPainter extends CustomPainter {
  final List<Offset?> points;
  _SigPainter(this.points);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.black
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    for (var i = 0; i < points.length - 1; i++) {
      final a = points[i];
      final b = points[i + 1];
      if (a != null && b != null) canvas.drawLine(a, b, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _SigPainter old) => true;
}
