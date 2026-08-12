import 'dart:io';
import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';
import 'file_picker.dart';
import 'pdf_service.dart';
import 'tools.dart';

class SplitPage extends StatefulWidget {
  const SplitPage({super.key});

  @override
  State<SplitPage> createState() => _SplitPageState();
}

class _SplitPageState extends State<SplitPage> {
  File? _source;
  final TextEditingController _rangesCtrl = TextEditingController(text: '1-1');
  bool _processing = false;
  List<File> _results = [];

  Future<void> _pickSource() async {
    final files = await PdfFilePicker.pickPdfs();
    if (files.isNotEmpty) {
      setState(() {
        _source = files.first;
        _results = [];
      });
    }
  }

  List<(int, int)> _parseRanges(String input) {
    final ranges = <(int, int)>[];
    final parts = input.split(RegExp(r'[,;\s]+'));
    for (final part in parts) {
      if (part.isEmpty) continue;
      if (part.contains('-')) {
        final se = part.split('-');
        if (se.length == 2) {
          final s = int.tryParse(se[0].trim());
          final e = int.tryParse(se[1].trim());
          if (s != null && e != null && s > 0 && e >= s) {
            ranges.add((s, e));
          }
        }
      } else {
        final n = int.tryParse(part.trim());
        if (n != null && n > 0) ranges.add((n, n));
      }
    }
    return ranges;
  }

  Future<void> _split() async {
    if (_source == null) {
      PdfFilePicker.showResult(context, 'Select a PDF first', isError: true);
      return;
    }
    final ranges = _parseRanges(_rangesCtrl.text);
    if (ranges.isEmpty) {
      PdfFilePicker.showResult(context, 'Enter valid page ranges (e.g. 1-3,5,7-9)', isError: true);
      return;
    }
    setState(() => _processing = true);
    try {
      final outs = await PdfService.splitPdf(_source!, ranges: ranges);
      setState(() {
        _results = outs;
        _processing = false;
      });
      if (mounted) {
        PdfFilePicker.showResult(context, 'Split into ${outs.length} file(s)');
      }
    } catch (e) {
      setState(() => _processing = false);
      if (mounted) {
        PdfFilePicker.showResult(context, 'Split failed: $e', isError: true);
      }
    }
  }

  @override
  void dispose() {
    _rangesCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Split PDF')),
      body: Stack(
        children: [
          ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                child: ListTile(
                  leading: const Icon(Icons.picture_as_pdf, color: Color(0xFFFFA726)),
                  title: Text(
                    _source == null ? 'No file selected' : p.basename(_source!.path),
                    style: GoogleFonts.inter(fontWeight: FontWeight.w500),
                  ),
                  subtitle: _source == null
                      ? const Text('Tap to choose PDF')
                      : FutureBuilder(
                          future: _source!.length(),
                          builder: (_, s) => Text(s.hasData ? PdfTools.formatBytes(s.data!) : '…'),
                        ),
                  trailing: ElevatedButton(
                    onPressed: _pickSource,
                    child: Text(_source == null ? 'Select' : 'Change'),
                  ),
                ),
              ),
              const Gap(20),
              Text('Page ranges', style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 15)),
              const Gap(8),
              TextField(
                controller: _rangesCtrl,
                decoration: InputDecoration(
                  hintText: 'e.g. 1-3, 5, 8-10',
                  filled: true,
                  fillColor: const Color(0xFF152238),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  helperText: 'Comma separated. Use dash for ranges.',
                ),
                style: GoogleFonts.inter(),
              ),
              const Gap(24),
              ElevatedButton.icon(
                onPressed: _source != null ? _split : null,
                icon: const Icon(Icons.call_split),
                label: const Text('Split PDF'),
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                  backgroundColor: const Color(0xFFEF6C00),
                ),
              ),
              if (_results.isNotEmpty) ...[
                const Gap(28),
                Text('Results', style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 15)),
                const Gap(10),
                ..._results.map((f) => Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        leading: const Icon(Icons.insert_drive_file, color: Colors.greenAccent),
                        title: Text(p.basename(f.path), style: GoogleFonts.inter(fontSize: 13)),
                        trailing: IconButton(
                          icon: const Icon(Icons.share),
                          onPressed: () => Share.shareXFiles([XFile(f.path)]),
                        ),
                      ),
                    )),
              ],
            ],
          ),
          if (_processing) const LoadingOverlay(message: 'Splitting PDF…'),
        ],
      ),
    );
  }
}
