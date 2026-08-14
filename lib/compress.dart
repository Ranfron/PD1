import 'dart:io';
import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';
import 'file_picker.dart';
import 'pdf_service.dart';
import 'tools.dart';

class CompressPage extends StatefulWidget {
  const CompressPage({super.key});

  @override
  State<CompressPage> createState() => _CompressPageState();
}

class _CompressPageState extends State<CompressPage> {
  File? _source;
  double _quality = 70;
  bool _processing = false;
  File? _result;
  int? _originalSize;
  int? _newSize;

  Future<void> _pick() async {
    final files = await PdfFilePicker.pickPdfs();
    if (files.isNotEmpty) {
      final size = await files.first.length();
      setState(() {
        _source = files.first;
        _originalSize = size;
        _result = null;
        _newSize = null;
      });
    }
  }

  Future<void> _compress() async {
    if (_source == null) return;
    setState(() => _processing = true);
    try {
      final out = await PdfService.compressPdf(_source!, quality: _quality.round());
      final newSize = await out.length();
      setState(() {
        _result = out;
        _newSize = newSize;
        _processing = false;
      });
      if (mounted) {
        PdfFilePicker.showResult(context, 'Compression finished');
      }
    } catch (e) {
      setState(() => _processing = false);
      if (mounted) {
        PdfFilePicker.showResult(context, 'Compress failed: $e', isError: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Compress PDF')),
      body: Stack(
        children: [
          ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                child: ListTile(
                  leading: const Icon(Icons.compress, color: Color(0xFFAB47BC)),
                  title: Text(
                    _source == null ? 'No file selected' : p.basename(_source!.path),
                    style: GoogleFonts.inter(fontWeight: FontWeight.w500),
                  ),
                  subtitle: _originalSize != null
                      ? Text(PdfTools.formatBytes(_originalSize!))
                      : const Text('Tap to choose PDF'),
                  trailing: ElevatedButton(
                    onPressed: _pick,
                    child: Text(_source == null ? 'Select' : 'Change'),
                  ),
                ),
              ),
              const Gap(28),
              Text(
                'Quality: ${_quality.round()}%',
                style: GoogleFonts.inter(fontWeight: FontWeight.w600),
              ),
              Slider(
                value: _quality,
                min: 20,
                max: 95,
                divisions: 15,
                label: '${_quality.round()}%',
                activeColor: const Color(0xFFAB47BC),
                onChanged: (v) => setState(() => _quality = v),
              ),
              Text(
                'Lower quality = smaller file (approximate)',
                style: GoogleFonts.inter(fontSize: 12, color: Colors.white54),
              ),
              const Gap(28),
              ElevatedButton.icon(
                onPressed: _source != null ? _compress : null,
                icon: const Icon(Icons.compress),
                label: const Text('Compress'),
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                  backgroundColor: const Color(0xFF7B1FA2),
                ),
              ),
              if (_result != null && _newSize != null) ...[
                const Gap(28),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF4A148C).withOpacity(0.3),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.purpleAccent.withOpacity(0.3)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Result', style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
                      const Gap(8),
                      Text(p.basename(_result!.path), style: const TextStyle(color: Colors.white70)),
                      const Gap(8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Original: ${PdfTools.formatBytes(_originalSize!)}'),
                          Text('New: ${PdfTools.formatBytes(_newSize!)}'),
                        ],
                      ),
                      const Gap(12),
                      ElevatedButton.icon(
                        onPressed: () => SharePlus.instance.share(ShareParams(files: [XFile(_result!.path)])),
                        icon: const Icon(Icons.share, size: 18),
                        label: const Text('Share'),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
          if (_processing) const LoadingOverlay(message: 'Compressing…'),
        ],
      ),
    );
  }
}
