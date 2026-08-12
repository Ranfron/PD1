import 'dart:io';
import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';
import 'file_picker.dart';
import 'pdf_service.dart';
import 'tools.dart';

class MergePage extends StatefulWidget {
  const MergePage({super.key});

  @override
  State<MergePage> createState() => _MergePageState();
}

class _MergePageState extends State<MergePage> {
  final List<File> _files = [];
  bool _processing = false;
  File? _result;

  Future<void> _addFiles() async {
    final picked = await PdfFilePicker.pickPdfs(allowMultiple: true);
    if (picked.isNotEmpty) {
      setState(() {
        _files.addAll(picked);
        _result = null;
      });
    }
  }

  void _removeAt(int index) {
    setState(() {
      _files.removeAt(index);
      _result = null;
    });
  }

  void _reorder(int oldIndex, int newIndex) {
    setState(() {
      if (newIndex > oldIndex) newIndex--;
      final item = _files.removeAt(oldIndex);
      _files.insert(newIndex, item);
      _result = null;
    });
  }

  Future<void> _merge() async {
    if (_files.length < 2) {
      PdfFilePicker.showResult(context, 'Select at least 2 PDFs', isError: true);
      return;
    }
    setState(() => _processing = true);
    try {
      final out = await PdfService.mergePdfs(_files);
      setState(() {
        _result = out;
        _processing = false;
      });
      if (mounted) {
        PdfFilePicker.showResult(context, 'Merged successfully!');
      }
    } catch (e) {
      setState(() => _processing = false);
      if (mounted) {
        PdfFilePicker.showResult(context, 'Merge failed: $e', isError: true);
      }
    }
  }

  Future<void> _shareResult() async {
    if (_result == null) return;
    await Share.shareXFiles([XFile(_result!.path)]);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Merge PDF')),
      body: Stack(
        children: [
          Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _addFiles,
                        icon: const Icon(Icons.add),
                        label: const Text('Add PDFs'),
                      ),
                    ),
                    const Gap(12),
                    ElevatedButton.icon(
                      onPressed: _files.length >= 2 ? _merge : null,
                      icon: const Icon(Icons.merge_type),
                      label: const Text('Merge'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF2E7D32),
                      ),
                    ),
                  ],
                ),
              ),
              if (_files.isEmpty)
                const Expanded(
                  child: EmptyState(
                    icon: Icons.merge_type_rounded,
                    title: 'No files selected',
                    subtitle: 'Add 2 or more PDF files to merge them into one document.',
                  ),
                )
              else
                Expanded(
                  child: ReorderableListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: _files.length,
                    onReorder: _reorder,
                    itemBuilder: (context, index) {
                      final f = _files[index];
                      return Card(
                        key: ValueKey(f.path),
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: const Color(0xFF1565C0).withOpacity(0.2),
                            child: Text(
                              '${index + 1}',
                              style: const TextStyle(color: Color(0xFF42A5F5)),
                            ),
                          ),
                          title: Text(
                            p.basename(f.path),
                            style: GoogleFonts.inter(fontSize: 14),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: FutureBuilder(
                            future: f.length(),
                            builder: (ctx, snap) {
                              if (!snap.hasData) return const Text('…');
                              return Text(PdfTools.formatBytes(snap.data!));
                            },
                          ),
                          trailing: IconButton(
                            icon: const Icon(Icons.close, size: 20),
                            onPressed: () => _removeAt(index),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              if (_result != null)
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.all(16),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1B5E20).withOpacity(0.3),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.green.withOpacity(0.4)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.check_circle, color: Colors.greenAccent, size: 20),
                          const Gap(8),
                          Text(
                            'Merged file ready',
                            style: GoogleFonts.inter(fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                      const Gap(8),
                      Text(
                        p.basename(_result!.path),
                        style: GoogleFonts.inter(fontSize: 13, color: Colors.white70),
                      ),
                      const Gap(12),
                      Row(
                        children: [
                          ElevatedButton.icon(
                            onPressed: _shareResult,
                            icon: const Icon(Icons.share, size: 18),
                            label: const Text('Share'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
            ],
          ),
          if (_processing) const LoadingOverlay(message: 'Merging PDFs…'),
        ],
      ),
    );
  }
}
