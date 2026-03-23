import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../theme/app_theme.dart';
import '../Documents/document_viewer_web.dart'
    if (dart.library.io) '../Documents/document_viewer_stub.dart';

class HtmlPreviewScreen extends StatefulWidget {
  final String assetPath;
  final String title;

  const HtmlPreviewScreen({
    super.key,
    required this.assetPath,
    required this.title,
  });

  @override
  State<HtmlPreviewScreen> createState() => _HtmlPreviewScreenState();
}

class _HtmlPreviewScreenState extends State<HtmlPreviewScreen> {
  String? _html;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadAsset();
  }

  Future<void> _loadAsset() async {
    final html = await rootBundle.loadString(widget.assetPath);
    if (mounted) setState(() { _html = html; _loading = false; });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgPrimary,
      appBar: AppBar(
        backgroundColor: AppColors.bgSurface,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_rounded, size: 18, color: AppColors.textSecondary),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          widget.title,
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(0.5),
          child: Container(height: 0.5, color: AppColors.border),
        ),
      ),
      body: _loading
          ? Center(child: CircularProgressIndicator(color: AppColors.accent, strokeWidth: 2))
          : HtmlBlobViewer(html: _html!),
    );
  }
}
