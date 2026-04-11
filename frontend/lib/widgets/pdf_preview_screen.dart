import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import '../theme/app_theme.dart';
import '../services/share_capability.dart';
import '../services/download_helper.dart';
import '../services/activity_log_service.dart';

class PdfPreviewScreen extends StatefulWidget {
  final String title;
  final Future<dynamic> Function() buildPdf;
  final String? shareFileName;
  final String? documentId;
  final String? documentType;

  const PdfPreviewScreen({
    super.key,
    required this.title,
    required this.buildPdf,
    this.shareFileName,
    this.documentId,
    this.documentType,
  });

  @override
  State<PdfPreviewScreen> createState() => _PdfPreviewScreenState();
}

class _PdfPreviewScreenState extends State<PdfPreviewScreen> {
  Uint8List? _cachedBytes;
  bool _isSharing = false;

  Future<Uint8List> _buildAndCache() async {
    if (_cachedBytes != null) return _cachedBytes!;
    final bytes = await widget.buildPdf();
    _cachedBytes = bytes as Uint8List;
    return _cachedBytes!;
  }

  Future<void> _handleShare() async {
    setState(() => _isSharing = true);
    if (widget.documentType != null && widget.documentId != null) {
      ActivityLogService().logShared(
        documentType: widget.documentType!,
        documentId: widget.documentId!,
      );
    }
    try {
      final bytes = await _buildAndCache();
      final fileName =
          widget.shareFileName ?? '${widget.title.replaceAll(' ', '_')}.pdf';
      final outcome = await sharePdfBytes(bytes, fileName, widget.title);
      if (!mounted) return;
      if (outcome == ShareOutcome.fallbackDownloaded) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Saved to Files')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Couldn\'t share PDF: $e')),
      );
    } finally {
      if (mounted) setState(() => _isSharing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = canUseNativeShareControl();

    return Scaffold(
      backgroundColor: AppColors.bgPrimary,
      appBar: AppBar(
        backgroundColor: AppColors.bgSurface,
        title: Text(
          widget.title,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
        leading: IconButton(
          icon: Icon(Icons.arrow_back_rounded,
              size: 18, color: AppColors.textSecondary),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          if (isMobile)
            IconButton(
              icon: Icon(Icons.ios_share_rounded,
                  size: 18, color: AppColors.textSecondary),
              tooltip: 'Share',
              onPressed: _isSharing ? null : _handleShare,
            ),
        ],
      ),
      body: PdfPreview(
        build: (format) async => _buildAndCache(),
        canChangePageFormat: false,
        canDebug: false,
        allowPrinting: !isMobile,
        allowSharing: !isMobile,
        pdfFileName: '${widget.title.replaceAll(' ', '_')}.pdf',
        actionBarTheme: PdfActionBarTheme(
          backgroundColor: AppColors.bgSurface,
          iconColor: AppColors.textSecondary,
          textStyle: TextStyle(color: AppColors.textSecondary, fontSize: 12),
        ),
      ),
    );
  }
}
