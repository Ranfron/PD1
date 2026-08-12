import 'dart:io';
import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:share_plus/share_plus.dart';
import 'package:open_filex/open_filex.dart';
import 'file_picker.dart';
import 'tools.dart';

class ViewerPage extends StatefulWidget {
  const ViewerPage({super.key});

  @override
  State<ViewerPage> createState() => _ViewerPageState();
}

class _ViewerPageState extends State<ViewerPage> {
  File? _file;
  bool _loading = false;
  PdfDocument? _document;

  Future<void> _pickAndOpen() async {
    setState(() => _loading = true);
    try {
      final files = await PdfFilePicker.pickPdfs();
      if (files.isEmpty) {
        setState(() => _loading = false);
        return;
      }
      final file = files.first;
      final doc = await PdfDocument.openFile(file.path);
      setState(() {
        _file = file;
        _document = doc;
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
      if (mounted) {
        PdfFilePicker.showResult(context, 'Failed to open: $e', isError: true);
      }
    }
  }

  Future<void> _share() async {
    if (_file == null) return;
    await Share.shareXFiles([XFile(_file!.path)]);
  }

  Future<void> _openExternal() async {
    if (_file == null) return;
    await OpenFilex.open(_file!.path);
  }

  @override
  void dispose() {
    _document?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_file != null ? _file!.path.split('/').last : 'PDF Viewer'),
        actions: [
          if (_file != null) ...[
            IconButton(
              icon: const Icon(Icons.share_rounded),
              onPressed: _share,
              tooltip: 'Share',
            ),
            IconButton(
              icon: const Icon(Icons.open_in_new_rounded),
              onPressed: _openExternal,
              tooltip: 'Open externally',
            ),
          ],
          IconButton(
            icon: const Icon(Icons.folder_open_rounded),
            onPressed: _pickAndOpen,
            tooltip: 'Open PDF',
          ),
        ],
      ),
      body: Stack(
        children: [
          if (_file == null)
            EmptyState(
              icon: Icons.picture_as_pdf_outlined,
              title: 'No PDF opened',
              subtitle: 'Tap the folder icon or button below to select a PDF file from your device.',
              actionLabel: 'Open PDF',
              onAction: _pickAndOpen,
            )
          else
            Column(
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  color: const Color(0xFF152238),
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline, size: 16, color: Colors.white54),
                      const Gap(8),
                      Expanded(
                        child: Text(
                          _file!.path,
                          style: GoogleFonts.inter(fontSize: 12, color: Colors.white54),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: PdfViewer.file(
                    _file!.path,
                    params: PdfViewerParams(
                      backgroundColor: const Color(0xFF0A1628),
                      loadingBannerBuilder: (context, bytesDownloaded, totalBytes) {
                        return const Center(
                          child: CircularProgressIndicator(color: Color(0xFF42A5F5)),
                        );
                      },
                    ),
                  ),
                ),
              ],
            ),
          if (_loading) const LoadingOverlay(message: 'Opening PDF…'),
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
