import 'dart:async';
import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path/path.dart' as p;
import 'package:permission_handler/permission_handler.dart';
import 'package:share_plus/share_plus.dart';
import 'file_picker.dart';
import 'ocr.dart';
import 'pp_ocr.dart';
import 'scanner_engine.dart';
import 'storage.dart';
import 'tools.dart';

class ScannerPage extends StatefulWidget {
  const ScannerPage({super.key});

  @override
  State<ScannerPage> createState() => _ScannerPageState();
}

class _ScannerPageState extends State<ScannerPage> with WidgetsBindingObserver {
  CameraController? _cam;
  List<CameraDescription> _cameras = [];
  bool _ready = false;
  bool _busy = false;
  bool _detecting = false;
  String _hint = 'Point at a document';
  ScanMode _mode = ScanMode.document;
  File? _lastScan;
  String _ocrText = '';
  Timer? _autoTimer;
  bool _autoRunning = false;
  DateTime _autoCooldownUntil = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initCamera();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _autoTimer?.cancel();
    _cam?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final c = _cam;
    if (c == null || !c.value.isInitialized) return;
    if (state == AppLifecycleState.inactive) {
      c.dispose();
      _cam = null;
      _ready = false;
      _autoTimer?.cancel();
    } else if (state == AppLifecycleState.resumed) {
      _initCamera();
    }
  }

  Future<void> _initCamera() async {
    final status = await Permission.camera.request();
    if (!status.isGranted) {
      if (mounted) {
        setState(() => _hint = 'Camera permission required');
      }
      return;
    }
    try {
      _cameras = await availableCameras();
      if (_cameras.isEmpty) {
        setState(() => _hint = 'No camera found');
        return;
      }
      final back = _cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => _cameras.first,
      );
      final controller = CameraController(
        back,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() {
        _cam = controller;
        _ready = true;
        _hint = _mode == ScanMode.card
            ? 'Align ID / card inside frame'
            : 'Align document · hold steady';
      });
      await ScannerEngine.resetAutoCapture();
      _startAutoDetection();
    } catch (e) {
      if (mounted) setState(() => _hint = 'Camera error: $e');
    }
  }

  void _startAutoDetection() {
    _autoTimer?.cancel();
    if (!_ready || _cam == null) return;
    _autoTimer = Timer.periodic(const Duration(milliseconds: 950), (_) {
      _autoDetectOnce();
    });
  }

  Future<void> _autoDetectOnce() async {
    if (_autoRunning || _busy || !_ready || _cam == null) return;
    if (DateTime.now().isBefore(_autoCooldownUntil)) return;
    _autoRunning = true;
    try {
      final shot = await _cam!.takePicture();
      final temp = File(shot.path);
      final stable = await ScannerEngine.checkStable(temp, mode: _mode);
      if (stable && mounted && !_busy) {
        _autoCooldownUntil = DateTime.now().add(const Duration(milliseconds: 1800));
        setState(() {
          _busy = true;
          _hint = 'Auto-capturing…';
        });
        try {
          final outDir = (await AppStorage.outputGeneral()).path;
          final scanned = await ScannerEngine.processScan(
            temp, mode: _mode, enhance: true, bw: false, outDir: outDir,
          );
          if (scanned != null && mounted) {
            setState(() {
              _lastScan = scanned;
              _ocrText = '';
              _hint = 'Scan saved';
            });
          }
        } finally {
          if (mounted) setState(() => _busy = false);
          await ScannerEngine.resetAutoCapture();
        }
      }
      if (await temp.exists()) await temp.delete();
    } catch (_) {
      // Camera may be temporarily busy while a manual capture is finishing.
    } finally {
      _autoRunning = false;
    }
  }

  Future<void> _captureAndProcess({bool auto = false}) async {
    final cam = _cam;
    if (cam == null || !cam.value.isInitialized || _busy) return;
    setState(() {
      _busy = true;
      _hint = auto ? 'Auto-capturing…' : 'Capturing…';
    });
    try {
      final shot = await cam.takePicture();
      final raw = File(shot.path);
      final outDir = (await AppStorage.outputGeneral()).path;
      final scanned = await ScannerEngine.processScan(
        raw,
        mode: _mode,
        enhance: true,
        bw: false,
        outDir: outDir,
      );
      if (scanned != null && mounted) {
        setState(() {
          _lastScan = scanned;
          _ocrText = '';
          _hint = 'Scan saved';
        });
      } else if (mounted) {
        setState(() => _hint = 'Scan failed');
      }
    } catch (e) {
      if (mounted) setState(() => _hint = 'Error: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
      await ScannerEngine.resetAutoCapture();
    }
  }

  Future<void> _pickGallery() async {
    final imgs = await PdfFilePicker.pickImages(allowMultiple: false);
    if (imgs.isEmpty) return;
    setState(() => _busy = true);
    try {
      final outDir = (await AppStorage.outputGeneral()).path;
      final scanned = await ScannerEngine.processScan(
        imgs.first,
        mode: _mode,
        enhance: true,
        outDir: outDir,
      );
      if (scanned != null && mounted) {
        setState(() {
          _lastScan = scanned;
          _ocrText = '';
          _hint = 'Scan from gallery ready';
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _runOcrOnScan() async {
    final f = _lastScan;
    if (f == null) return;
    setState(() => _busy = true);
    try {
      var text = await PpOcr.processImage(f);
      if (text.trim().isEmpty) {
        // Fallback path: open OCR page logic via empty → user can use OCR tool
        text = '';
      }
      if (mounted) {
        setState(() {
          _ocrText = text;
          _busy = false;
          _hint = text.isEmpty
              ? 'OCR empty — open OCR tool or install PP-OCR models'
              : 'OCR done';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _hint = 'OCR failed: $e';
        });
      }
    }
  }

  void _toggleMode() {
    setState(() {
      _mode =
          _mode == ScanMode.document ? ScanMode.card : ScanMode.document;
      _hint = _mode == ScanMode.card
          ? 'ID / Card mode'
          : 'Document mode (A4 / forms)';
    });
    ScannerEngine.resetAutoCapture();
    _autoCooldownUntil = DateTime.now().add(const Duration(milliseconds: 500));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Document Scanner'),
        backgroundColor: Colors.black,
        actions: [
          TextButton(
            onPressed: _busy ? null : _toggleMode,
            child: Text(
              _mode == ScanMode.card ? 'CARD' : 'DOC',
              style: const TextStyle(color: Color(0xFF42A5F5)),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.photo_library_outlined),
            onPressed: _busy ? null : _pickGallery,
          ),
        ],
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (_ready && _cam != null)
            Center(child: CameraPreview(_cam!))
          else
            Center(
              child: Text(
                _hint,
                style: const TextStyle(color: Colors.white70),
              ),
            ),
          // Frame guide
          if (_ready)
            IgnorePointer(
              child: CustomPaint(
                painter: _GuidePainter(card: _mode == ScanMode.card),
                size: Size.infinite,
              ),
            ),
          // Bottom controls
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Colors.black.withOpacity(0.85),
                  ],
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _hint,
                    style: GoogleFonts.inter(
                      color: Colors.white70,
                      fontSize: 13,
                    ),
                  ),
                  const Gap(12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      IconButton(
                        iconSize: 32,
                        onPressed: _busy ? null : _pickGallery,
                        icon: const Icon(Icons.image, color: Colors.white),
                      ),
                      GestureDetector(
                        onTap: _busy ? null : () => _captureAndProcess(),
                        child: Container(
                          width: 72,
                          height: 72,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 4),
                          ),
                          child: Container(
                            margin: const EdgeInsets.all(4),
                            decoration: const BoxDecoration(
                              color: Color(0xFFEF5350),
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                      ),
                      IconButton(
                        iconSize: 32,
                        onPressed: _lastScan == null || _busy
                            ? null
                            : _runOcrOnScan,
                        icon: const Icon(
                          Icons.document_scanner,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          // Result strip
          if (_lastScan != null)
            Positioned(
              left: 12,
              right: 12,
              bottom: 140,
              child: Material(
                color: const Color(0xFF152238),
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.file(
                          _lastScan!,
                          width: 56,
                          height: 72,
                          fit: BoxFit.cover,
                        ),
                      ),
                      const Gap(10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              p.basename(_lastScan!.path),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                              ),
                            ),
                            if (_ocrText.isNotEmpty)
                              Text(
                                _ocrText,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white54,
                                  fontSize: 11,
                                ),
                              ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.share, color: Colors.white70),
                        onPressed: () =>
                            Share.shareXFiles([XFile(_lastScan!.path)]),
                      ),
                      IconButton(
                        icon: const Icon(
                          Icons.text_snippet_outlined,
                          color: Color(0xFF42A5F5),
                        ),
                        onPressed: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const OcrPage(),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),
          if (_busy) const LoadingOverlay(message: 'Processing scan…'),
        ],
      ),
    );
  }
}

class _GuidePainter extends CustomPainter {
  final bool card;
  _GuidePainter({required this.card});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF42A5F5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    final w = size.width * (card ? 0.72 : 0.82);
    final h = size.height * (card ? 0.28 : 0.55);
    final rect = Rect.fromCenter(
      center: Offset(size.width / 2, size.height / 2 - 20),
      width: w,
      height: h,
    );
    final r = RRect.fromRectAndRadius(rect, const Radius.circular(8));
    canvas.drawRRect(r, paint);
    // corner ticks
    const tick = 18.0;
    final corners = [
      rect.topLeft,
      rect.topRight,
      rect.bottomRight,
      rect.bottomLeft,
    ];
    final dirs = [
      [1.0, 0.0, 0.0, 1.0],
      [-1.0, 0.0, 0.0, 1.0],
      [-1.0, 0.0, 0.0, -1.0],
      [1.0, 0.0, 0.0, -1.0],
    ];
    final thick = Paint()
      ..color = Colors.white
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < 4; i++) {
      final c = corners[i];
      final d = dirs[i];
      canvas.drawLine(c, c + Offset(d[0] * tick, d[1] * tick), thick);
      canvas.drawLine(c, c + Offset(d[2] * tick, d[3] * tick), thick);
    }
  }

  @override
  bool shouldRepaint(covariant _GuidePainter oldDelegate) =>
      oldDelegate.card != card;
}
