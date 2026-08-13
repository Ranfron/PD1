import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:gap/gap.dart';
import 'package:google_fonts/google_fonts.dart';
import 'viewer.dart';
import 'merge.dart';
import 'split.dart';
import 'compress.dart';
import 'convert.dart';
import 'ocr.dart';
import 'annotate.dart';
import 'settings.dart';
import 'advanced_edit.dart';
import 'pro_tools.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final List<_ToolItem> _tools = const [
    _ToolItem(
      title: 'Open PDF',
      subtitle: 'View & browse files',
      icon: Icons.folder_open_rounded,
      color: Color(0xFF42A5F5),
      route: 'viewer',
    ),
    _ToolItem(
      title: 'Merge PDF',
      subtitle: 'Combine multiple files',
      icon: Icons.merge_type_rounded,
      color: Color(0xFF66BB6A),
      route: 'merge',
    ),
    _ToolItem(
      title: 'Split PDF',
      subtitle: 'Extract pages / ranges',
      icon: Icons.call_split_rounded,
      color: Color(0xFFFFA726),
      route: 'split',
    ),
    _ToolItem(
      title: 'Compress',
      subtitle: 'Reduce file size',
      icon: Icons.compress_rounded,
      color: Color(0xFFAB47BC),
      route: 'compress',
    ),
    _ToolItem(
      title: 'Convert',
      subtitle: 'PDF ↔ Images / Text',
      icon: Icons.transform_rounded,
      color: Color(0xFF26C6DA),
      route: 'convert',
    ),
    _ToolItem(
      title: 'OCR',
      subtitle: 'Extract text offline',
      icon: Icons.document_scanner_rounded,
      color: Color(0xFFEF5350),
      route: 'ocr',
    ),
    _ToolItem(
      title: 'Annotate',
      subtitle: 'Highlight, draw, notes',
      icon: Icons.edit_note_rounded,
      color: Color(0xFFFFEE58),
      route: 'annotate',
    ),
    _ToolItem(
      title: 'Advanced Edit',
      subtitle: 'Protect, watermark, redact…',
      icon: Icons.auto_fix_high,
      color: Color(0xFFEC407A),
      route: 'advanced',
    ),
    _ToolItem(
      title: 'Pro Tools',
      subtitle: 'Text, image, forms, sign',
      icon: Icons.design_services_rounded,
      color: Color(0xFF7E57C2),
      route: 'pro',
    ),
    _ToolItem(
      title: 'Settings',
      subtitle: 'App preferences',
      icon: Icons.settings_rounded,
      color: Color(0xFF90A4AE),
      route: 'settings',
    ),
  ];

  void _openTool(String route) {
    Widget page;
    switch (route) {
      case 'viewer':
        page = const ViewerPage();
        break;
      case 'merge':
        page = const MergePage();
        break;
      case 'split':
        page = const SplitPage();
        break;
      case 'compress':
        page = const CompressPage();
        break;
      case 'convert':
        page = const ConvertPage();
        break;
      case 'ocr':
        page = const OcrPage();
        break;
      case 'annotate':
        page = const AnnotatePage();
        break;
      case 'advanced':
        page = const AdvancedEditPage();
        break;
      case 'pro':
        page = const ProToolsPage();
        break;
      case 'settings':
        page = const SettingsPage();
        break;
      default:
        return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => page),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFF1565C0), Color(0xFF00BCD4)],
                            ),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: const Icon(Icons.picture_as_pdf_rounded,
                              color: Colors.white, size: 28),
                        ),
                        const Gap(14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'PDF Power',
                                style: GoogleFonts.inter(
                                  fontSize: 26,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                ),
                              ),
                              Text(
                                'Full Offline Editor',
                                style: GoogleFonts.inter(
                                  fontSize: 13,
                                  color: Colors.white60,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          onPressed: () => _openTool('settings'),
                          icon: const Icon(Icons.settings_outlined),
                          color: Colors.white70,
                        ),
                      ],
                    ).animate().fadeIn(duration: 400.ms).slideX(begin: -0.05),
                    const Gap(24),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            const Color(0xFF1565C0).withOpacity(0.35),
                            const Color(0xFF0D47A1).withOpacity(0.2),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: const Color(0xFF42A5F5).withOpacity(0.3)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.lock_rounded, color: Color(0xFF00E5FF), size: 22),
                          const Gap(12),
                          Expanded(
                            child: Text(
                              '100% Offline • No cloud • Your files stay on device',
                              style: GoogleFonts.inter(
                                fontSize: 13,
                                color: Colors.white.withOpacity(0.9),
                                height: 1.3,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ).animate().fadeIn(delay: 150.ms, duration: 400.ms),
                    const Gap(28),
                    Text(
                      'Tools',
                      style: GoogleFonts.inter(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                    const Gap(14),
                  ],
                ),
              ),
            ),
           SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              sliver: SliverGrid(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 1.35,
                ),
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final tool = _tools[index];
                    return _ToolCard(
                      tool: tool,
                      onTap: () => _openTool(tool.route),
                    ).animate().fadeIn(
                          delay: (80 * index).ms,
                          duration: 350.ms,
                        ).scale(
                          begin: const Offset(0.92, 0.92),
                          curve: Curves.easeOut,
                        );
                  },
                  childCount: _tools.length,
                ),
              ),
            ),
            const SliverToBoxAdapter(child: Gap(32)),
          ],
        ),
      ),
    );
  }
}

class _ToolItem {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final String route;

  const _ToolItem({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.route,
  });
}

class _ToolCard extends StatelessWidget {
  final _ToolItem tool;
  final VoidCallback onTap;

  const _ToolCard({required this.tool, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF152238),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: tool.color.withOpacity(0.25)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: tool.color.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(tool.icon, color: tool.color, size: 26),
              ),
              const Gap(12),
              Text(
                tool.title,
                style: GoogleFonts.inter(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
              const Gap(2),
              Text(
                tool.subtitle,
                style: GoogleFonts.inter(
                  fontSize: 11,
                  color: Colors.white54,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
