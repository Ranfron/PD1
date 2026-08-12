import 'dart:io';
import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';
import 'file_picker.dart';
import 'pdf_service.dart';
import 'tools.dart';

class ConvertPage extends StatefulWidget {
  const ConvertPage({super.key});

  @override
  State<ConvertPage> createState() => _ConvertPageState();
}

class _ConvertPageState extends State<ConvertPage> with SingleTickerProviderStateMixin {
  late TabController _tab;
  final List<File> _images = [];
  bool _processing = false;
  File? _result;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  Future<void> _pickImages() async {
    final imgs = await PdfFilePicker.pickImages(allowMultiple: true);
    if (imgs.isNotEmpty) {
      setState(() {
        _images.addAll(imgs);
        _result = null;
      });
    }
  }

  void _removeImage(int i) {
    setState(() {
      _images.removeAt(i);
      _result = null;
    });
  }

  Future<void> _imagesToPdf() async {
    if (_images.isEmpty) {
      PdfFilePicker.showResult(context, 'Add at least one image', isError: true);
      return;
    }
    setState(() => _processing = true);
    try {
      final out = await PdfService.imagesToPdf(_images);
      setState(() {
        _result = out;
        _processing = false;
      });
      if (mounted) PdfFilePicker.showResult(context, 'PDF created!');
    } catch (e) {
      setState(() => _processing = false);
      if (mounted) PdfFilePicker.showResult(context, 'Failed: $e', isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Convert'),
        bottom: TabBar(
          controller: _tab,
          indicatorColor: const Color(0xFF26C6DA),
          tabs: const [
            Tab(text: 'Images → PDF'),
            Tab(text: 'PDF → Images'),
          ],
        ),
      ),
      body: Stack(
        children: [
          TabBarView(
            controller: _tab,
            children: [
              // Images to PDF
              Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: _pickImages,
                            icon: const Icon(Icons.add_photo_alternate),
                            label: const Text('Add Images'),
                          ),
                        ),
                        const Gap(12),
                        ElevatedButton.icon(
                          onPressed: _images.isNotEmpty ? _imagesToPdf : null,
                          icon: const Icon(Icons.picture_as_pdf),
                          label: const Text('Create PDF'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF00838F),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (_images.isEmpty)
                    const Expanded(
                      child: EmptyState(
                        icon: Icons.image_outlined,
                        title: 'No images',
                        subtitle: 'Add photos or scanned pages to convert into a PDF.',
                      ),
                    )
                  else
                    Expanded(
                      child: ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: _images.length,
                        itemBuilder: (_, i) {
                          final f = _images[i];
                          return Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            child: ListTile(
                              leading: ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: Image.file(
                                  f,
                                  width: 48,
                                  height: 48,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) =>
                                      const Icon(Icons.broken_image),
                                ),
                              ),
                              title: Text(
                                p.basename(f.path),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.inter(fontSize: 13),
                              ),
                              trailing: IconButton(
                                icon: const Icon(Icons.close, size: 20),
                                onPressed: () => _removeImage(i),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  if (_result != null)
                    Container(
                      margin: const EdgeInsets.all(16),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFF006064).withOpacity(0.3),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.check_circle, color: Colors.cyanAccent),
                          const Gap(10),
                          Expanded(
                            child: Text(
                              p.basename(_result!.path),
                              style: GoogleFonts.inter(fontSize: 13),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.share),
                            onPressed: () => Share.shareXFiles([XFile(_result!.path)]),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
              // PDF to Images (placeholder – requires rendering engine)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.image_search, size: 64, color: Colors.white24),
                      Gap(16),
                      Text(
                        'PDF → Images',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: Colors.white70),
                      ),
                      Gap(8),
                      Text(
                        'Full page rendering to images requires MuPDF or pdfrx rasterization.\n'
                        'Native layer can be added later for high-quality export.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white38, height: 1.4),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          if (_processing) const LoadingOverlay(message: 'Converting…'),
        ],
      ),
    );
  }
}
