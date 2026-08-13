import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'tools.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool _darkMode = true;
  bool _keepOriginal = true;
  String _defaultQuality = '70';
  String _outputPath = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final dir = await getApplicationDocumentsDirectory();
    setState(() {
      _darkMode = prefs.getBool('darkMode') ?? true;
      _keepOriginal = prefs.getBool('keepOriginal') ?? true;
      _defaultQuality = prefs.getString('defaultQuality') ?? '70';
      _outputPath = '${dir.path}/PDF_Power_Output';
    });
  }

  Future<void> _save(String key, dynamic value) async {
    final prefs = await SharedPreferences.getInstance();
    if (value is bool) await prefs.setBool(key, value);
    if (value is String) await prefs.setString(key, value);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _sectionTitle('Appearance'),
          SwitchListTile(
            title: const Text('Dark mode'),
            subtitle: const Text('Always on for this build'),
            value: _darkMode,
            activeColor: const Color(0xFF42A5F5),
            onChanged: (v) {
              setState(() => _darkMode = v);
              _save('darkMode', v);
            },
          ),
          const Gap(16),
          _sectionTitle('Output'),
          ListTile(
            title: const Text('Output folder'),
            subtitle: Text(
              _outputPath,
              style: GoogleFonts.inter(fontSize: 12, color: Colors.white54),
            ),
            leading: const Icon(Icons.folder_special_outlined),
          ),
          SwitchListTile(
            title: const Text('Keep original files'),
            subtitle: const Text('Do not delete source after processing'),
            value: _keepOriginal,
            activeColor: const Color(0xFF42A5F5),
            onChanged: (v) {
              setState(() => _keepOriginal = v);
              _save('keepOriginal', v);
            },
          ),
          ListTile(
            title: const Text('Default compress quality'),
            subtitle: Text('$_defaultQuality%'),
            trailing: DropdownButton<String>(
              value: _defaultQuality,
              dropdownColor: const Color(0xFF1A2A40),
              items: ['40', '55', '70', '85']
                  .map((e) => DropdownMenuItem(value: e, child: Text('$e%')))
                  .toList(),
              onChanged: (v) {
                if (v == null) return;
                setState(() => _defaultQuality = v);
                _save('defaultQuality', v);
              },
            ),
          ),
          const Gap(24),
          _sectionTitle('About'),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
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
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.picture_as_pdf, color: Colors.white),
                      ),
                      const Gap(14),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            PdfTools.appName,
                            style: GoogleFonts.inter(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            'v${PdfTools.version}',
                            style: GoogleFonts.inter(color: Colors.white54, fontSize: 13),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const Gap(16),
                  const Text(
                    'Advanced offline PDF editor.\n'
                    'PDF engine: MuPDF 1.28.x (native fitz) + Dart fallback.\n'
                    'OCR: ML Kit (default) + optional PaddleOCR-VL-1.6.\n'
                    'Viewer: pdfrx · License note: MuPDF is AGPL.',
                    style: TextStyle(fontSize: 13, color: Colors.white60, height: 1.45),
                  ),
                  const Gap(12),
                  const Text(
                    '100% Offline • No analytics • No cloud',
                    style: TextStyle(fontSize: 12, color: Color(0xFF00E5FF)),
                  ),
                ],
              ),
            ),
          ),
          const Gap(32),
        ],
      ),
    );
  }

  Widget _sectionTitle(String t) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        t,
        style: GoogleFonts.inter(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: Colors.white54,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}
