import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'mupdf_service.dart';
import 'pp_ocr.dart';
import 'ocr_engine.dart';
import 'pp_ocr_model_manager.dart';

enum PdfObjectType { text, image, table, stamp, signature, other }

/// Hierarchy: block > line > word
enum SelectLevel { word, line, block }

class PdfRegionObject {
  final PdfObjectType type;
  final SelectLevel level;
  final List<double> bbox; // page coords [x0,y0,x1,y1]
  final String text;
  final double confidence;
  final double rotation;
  final String? parentId;
  final List<List<double>>? polygon;
  final String id;

  const PdfRegionObject({
    required this.type,
    required this.bbox,
    this.level = SelectLevel.word,
    this.text = '',
    this.confidence = 1.0,
    this.rotation = 0,
    this.parentId,
    this.polygon,
    required this.id,
  });

  double get x0 => bbox[0];
  double get y0 => bbox[1];
  double get x1 => bbox[2];
  double get y1 => bbox[3];
  double get area => math.max(1.0, (x1 - x0) * (y1 - y0));

  bool contains(double x, double y, {double pad = 3}) =>
      x >= x0 - pad && x <= x1 + pad && y >= y0 - pad && y <= y1 + pad;

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type.name,
        'level': level.name,
        'bbox': bbox,
        'text': text,
        'confidence': confidence,
        'rotation': rotation,
        'parentId': parentId,
        if (polygon != null) 'polygon': polygon,
      };

  factory PdfRegionObject.fromJson(Map<String, dynamic> j) {
    final t = PdfObjectType.values.firstWhere(
      (e) => e.name == (j['type'] ?? 'text'),
      orElse: () => PdfObjectType.text,
    );
    final lv = SelectLevel.values.firstWhere(
      (e) => e.name == (j['level'] ?? 'word'),
      orElse: () => SelectLevel.word,
    );
    final b =
        (j['bbox'] as List?)?.map((e) => (e as num).toDouble()).toList() ??
            [0.0, 0.0, 0.0, 0.0];
    while (b.length < 4) {
      b.add(0);
    }
    return PdfRegionObject(
      id: '${j['id'] ?? UniqueKeyString.next()}',
      type: t,
      level: lv,
      bbox: b,
      text: '${j['text'] ?? ''}',
      confidence: (j['confidence'] as num?)?.toDouble() ?? 1.0,
      rotation: (j['rotation'] as num?)?.toDouble() ?? 0,
      parentId: j['parentId']?.toString(),
      polygon: (j['polygon'] as List?)
          ?.whereType<List>()
          .map((p) => p.map((e) => (e as num).toDouble()).toList())
          .toList(),
    );
  }
}

class UniqueKeyString {
  static int _n = 0;
  static String next() => 'o${_n++}';
}

class PageAnalysis {
  final int page;
  final double width;
  final double height;
  final List<PdfRegionObject> objects;
  final DateTime analyzedAt;
  final String source; // mupdf | mlkit | pp_ocr

  PageAnalysis({
    required this.page,
    required this.width,
    required this.height,
    required this.objects,
    this.source = 'mupdf',
    DateTime? analyzedAt,
  }) : analyzedAt = analyzedAt ?? DateTime.now();
}

/// Maps viewer (screen) ↔ PDF page coordinates.
class PageCoordMapper {
  final double pageWidth;
  final double pageHeight;
  final double viewWidth;
  final double viewHeight;
  final double scale;
  final double offsetX;
  final double offsetY;

  PageCoordMapper({
    required this.pageWidth,
    required this.pageHeight,
    required this.viewWidth,
    required this.viewHeight,
  })  : scale = _calcScale(pageWidth, pageHeight, viewWidth, viewHeight),
        offsetX = (viewWidth -
                pageWidth *
                    _calcScale(pageWidth, pageHeight, viewWidth, viewHeight)) /
            2,
        offsetY = (viewHeight -
                pageHeight *
                    _calcScale(pageWidth, pageHeight, viewWidth, viewHeight)) /
            2;

  static double _calcScale(double pw, double ph, double vw, double vh) {
    if (pw <= 0 || ph <= 0) return 1;
    return math.min(vw / pw, vh / ph);
  }

  /// Screen (local viewer) → page PDF coords.
  (double, double) toPage(double sx, double sy) {
    final px = (sx - offsetX) / scale;
    final py = (sy - offsetY) / scale;
    return (px.clamp(0, pageWidth), py.clamp(0, pageHeight));
  }

  /// Page → screen.
  (double, double) toScreen(double px, double py) {
    return (px * scale + offsetX, py * scale + offsetY);
  }

  List<double> bboxToScreen(List<double> b) {
    final (x0, y0) = toScreen(b[0], b[1]);
    final (x1, y1) = toScreen(b[2], b[3]);
    return [x0, y0, x1, y1];
  }
}

class PdfEditEngine {
  final Map<int, PageAnalysis> _cache = {};
  final List<_EditOp> _undo = [];
  final List<_EditOp> _redo = [];
  File? _document;
  final TextRecognizer _mlkit =
      TextRecognizer(script: TextRecognitionScript.devanagiri);

  double defaultPageWidth = 595;
  double defaultPageHeight = 842;

  File? get document => _document;

  void open(File pdf) {
    _document = pdf;
    _cache.clear();
    _undo.clear();
    _redo.clear();
  }

  void close() {
    _document = null;
    _cache.clear();
    _undo.clear();
    _redo.clear();
    _mlkit.close();
  }

  void invalidatePage(int page) => _cache.remove(page);

  PageAnalysis? cached(int page) => _cache[page];

  Future<void> refreshPageSize(int page) async {
    final doc = _document;
    if (doc == null) return;
    final info = await MuPdfService.info(doc.path);
    // page size not always in info — keep defaults; caller can set
    if (info != null && info['pageCount'] != null) {
      // no-op size
    }
  }

  /// Full analysis: page size → PP-OCR → render+ML Kit → MuPDF text.
  Future<PageAnalysis> analyzePage(
    int page, {
    bool force = false,
    double? width,
    double? height,
    File? renderedPageImage,
  }) async {
    if (!force && _cache.containsKey(page)) return _cache[page]!;
    final doc = _document;
    if (doc == null) {
      return PageAnalysis(
        page: page,
        width: width ?? defaultPageWidth,
        height: height ?? defaultPageHeight,
        objects: [],
      );
    }

    // Exact page size from MuPDF
    var pw = width ?? defaultPageWidth;
    var ph = height ?? defaultPageHeight;
    final size = await MuPdfService.pageSize(doc, page: page);
    if (size != null) {
      pw = size.width;
      ph = size.height;
      defaultPageWidth = pw;
      defaultPageHeight = ph;
    }

    List<PdfRegionObject> objects = [];
    var source = 'mupdf';

    // 1) PP-OCR structured (DET + Devanagari REC)
    final engine = await OcrEngine.getSelected();
    final ppReady = await PpOcrModelManager.isReady();
    final wantPp = engine == OcrEngineType.ppOcr ||
        (engine == OcrEngineType.auto && ppReady);
    if (wantPp && ppReady) {
      final structured = await PpOcr.analyzePageStructured(
        pdfPath: doc.path,
        page: page,
      );
      if (structured != null && structured.isNotEmpty) {
        objects = structured;
        source = 'pp_ocr';
      }
    }

    // 2) Auto-render page + ML Kit word/line/block map
    File? pageImg = renderedPageImage;
    if (objects.isEmpty && pageImg == null) {
      pageImg = await MuPdfService.renderPage(doc, page: page, dpi: 144);
    }
    if (objects.isEmpty && pageImg != null) {
      final ml = await _analyzeWithMlKit(pageImg, pw, ph);
      if (ml.isNotEmpty) {
        objects = ml;
        source = 'mlkit';
      }
    }

    // 3) MuPDF text fallback
    if (objects.isEmpty) {
      final text =
          await MuPdfService.extractText(doc, start: page, end: page);
      if (text != null && text.trim().isNotEmpty) {
        objects = [
          PdfRegionObject(
            id: UniqueKeyString.next(),
            type: PdfObjectType.text,
            level: SelectLevel.block,
            bbox: [36, 36, pw - 36, ph - 36],
            text: text.trim(),
            confidence: 0.85,
          ),
        ];
        source = 'mupdf';
      }
    }

    final analysis = PageAnalysis(
      page: page,
      width: pw,
      height: ph,
      objects: objects,
      source: source,
    );
    _cache[page] = analysis;
    return analysis;
  }

  Future<List<PdfRegionObject>> _analyzeWithMlKit(
    File image,
    double pageW,
    double pageH,
  ) async {
    try {
      final input = InputImage.fromFile(image);
      final result = await _mlkit.processImage(input);
      // Image pixel size for scale → page
      final bytes = await image.readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final imgW = frame.image.width.toDouble();
      final imgH = frame.image.height.toDouble();
      frame.image.dispose();
      final sx = pageW / imgW;
      final sy = pageH / imgH;

      final objects = <PdfRegionObject>[];
      var bi = 0;
      for (final block in result.blocks) {
        final blockId = 'b${bi++}';
        final bb = block.boundingBox;
        objects.add(PdfRegionObject(
          id: blockId,
          type: PdfObjectType.text,
          level: SelectLevel.block,
          bbox: [
            bb.left * sx,
            bb.top * sy,
            bb.right * sx,
            bb.bottom * sy,
          ],
          text: block.text,
          confidence: 0.95,
        ));
        var li = 0;
        for (final line in block.lines) {
          final lineId = '${blockId}_l${li++}';
          final lb = line.boundingBox;
          objects.add(PdfRegionObject(
            id: lineId,
            type: PdfObjectType.text,
            level: SelectLevel.line,
            parentId: blockId,
            bbox: [
              lb.left * sx,
              lb.top * sy,
              lb.right * sx,
              lb.bottom * sy,
            ],
            text: line.text,
            confidence: 0.95,
          ));
          var wi = 0;
          for (final el in line.elements) {
            final eb = el.boundingBox;
            objects.add(PdfRegionObject(
              id: '${lineId}_w${wi++}',
              type: PdfObjectType.text,
              level: SelectLevel.word,
              parentId: lineId,
              bbox: [
                eb.left * sx,
                eb.top * sy,
                eb.right * sx,
                eb.bottom * sy,
              ],
              text: el.text,
              confidence: 0.95,
            ));
          }
        }
      }
      return objects;
    } catch (_) {
      return [];
    }
  }

  /// Hierarchical select: preferred level (tap=word, longPress=line/block).
  Future<PdfRegionObject?> selectAt(
    int page,
    double pageX,
    double pageY, {
    SelectLevel prefer = SelectLevel.word,
  }) async {
    final a = await analyzePage(page);
    final hits = a.objects.where((o) => o.contains(pageX, pageY)).toList();
    if (hits.isEmpty) return null;

    // Prefer requested level, else nearest smaller, else smallest area
    final preferred = hits.where((o) => o.level == prefer).toList();
    final pool = preferred.isNotEmpty ? preferred : hits;
    pool.sort((a, b) => a.area.compareTo(b.area));
    return pool.first;
  }

  Future<List<PdfRegionObject>> selectRegion(
    int page,
    double x0,
    double y0,
    double x1,
    double y1, {
    SelectLevel level = SelectLevel.word,
  }) async {
    final a = await analyzePage(page);
    final rx0 = math.min(x0, x1);
    final ry0 = math.min(y0, y1);
    final rx1 = math.max(x0, x1);
    final ry1 = math.max(y0, y1);
    return a.objects.where((o) {
      if (o.level != level && level == SelectLevel.word) {
        // include words primarily
      }
      final cx = (o.x0 + o.x1) / 2;
      final cy = (o.y0 + o.y1) / 2;
      return cx >= rx0 && cx <= rx1 && cy >= ry0 && cy <= ry1;
    }).toList();
  }

  /// Dual-mode replace:
  /// - digital (mupdf source): FreeText local patch
  /// - scanned (mlkit/pp_ocr): redact old pixels region then FreeText overlay
  Future<File?> replaceText(PdfRegionObject obj, String newText,
      {int page = 1}) async {
    final doc = _document;
    if (doc == null) return null;
    final src = _cache[page]?.source ?? 'mupdf';
    final scanned = src == 'mlkit' || src == 'pp_ocr';

    File? working = doc;
    if (scanned) {
      // Remove original ink/pixels under bbox (local patch)
      working = await MuPdfService.addRedaction(
        doc,
        page: page,
        x0: obj.x0,
        y0: obj.y0,
        x1: obj.x1,
        y1: obj.y1,
      );
      if (working != null) {
        working = await MuPdfService.applyRedactions(working) ?? working;
      } else {
        working = doc;
      }
    }

    final out = await MuPdfService.addFreeText(
      working!,
      page: page,
      text: newText,
      x0: obj.x0,
      y0: obj.y0,
      x1: obj.x1,
      y1: math.max(obj.y1, obj.y0 + 14),
    );
    if (out != null) {
      _pushUndo(doc, out);
      open(out);
      invalidatePage(page);
    }
    return out;
  }

  Future<File?> addText(int page, String text,
      {double x0 = 50,
      double y0 = 50,
      double x1 = 250,
      double y1 = 100}) async {
    final doc = _document;
    if (doc == null) return null;
    final out = await MuPdfService.addFreeText(
      doc,
      page: page,
      text: text,
      x0: x0,
      y0: y0,
      x1: x1,
      y1: y1,
    );
    if (out != null) {
      _pushUndo(doc, out);
      open(out);
      invalidatePage(page);
    }
    return out;
  }

  Future<File?> addImage(int page, File image,
      {double x0 = 50,
      double y0 = 50,
      double x1 = 200,
      double y1 = 150}) async {
    final doc = _document;
    if (doc == null) return null;
    final out = await MuPdfService.addStampImage(
      doc,
      image: image,
      page: page,
      x0: x0,
      y0: y0,
      x1: x1,
      y1: y1,
    );
    if (out != null) {
      _pushUndo(doc, out);
      open(out);
      invalidatePage(page);
    }
    return out;
  }

  Future<File?> removeRegion(int page, PdfRegionObject obj) async {
    final doc = _document;
    if (doc == null) return null;
    var out = await MuPdfService.addRedaction(
      doc,
      page: page,
      x0: obj.x0,
      y0: obj.y0,
      x1: obj.x1,
      y1: obj.y1,
    );
    if (out == null) return null;
    out = await MuPdfService.applyRedactions(out);
    if (out != null) {
      _pushUndo(doc, out);
      open(out);
      invalidatePage(page);
    }
    return out;
  }

  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;

  File? undo() {
    if (_undo.isEmpty || _document == null) return null;
    final op = _undo.removeLast();
    _redo.add(_EditOp(before: _document!, after: op.after));
    open(op.before);
    _cache.clear();
    return op.before;
  }

  File? redo() {
    if (_redo.isEmpty) return null;
    final op = _redo.removeLast();
    _undo.add(_EditOp(before: op.before, after: op.after));
    open(op.after);
    _cache.clear();
    return op.after;
  }

  void _pushUndo(File before, File after) {
    _undo.add(_EditOp(before: before, after: after));
    _redo.clear();
    if (_undo.length > 40) _undo.removeAt(0);
  }
}

class _EditOp {
  final File before;
  final File after;
  _EditOp({required this.before, required this.after});
}
