import 'dart:convert';
import 'dart:typed_data';
import 'dart:js_interop';
import 'package:web/web.dart' as web;
import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import '../../services/share_capability.dart';
import '../../services/download_helper.dart';
import '../Files/file_viewer_web.dart'
    if (dart.library.io) '../Files/file_viewer_stub.dart';

class LetterHtmlViewerScreen extends StatefulWidget {
  final String title;
  final String html;
  final VoidCallback? onGeneratePdf;

  /// Fetches PDF bytes for sharing. Return `null` to silently cancel (e.g.
  /// the caller showed a dialog and the user tapped Cancel). Throw on
  /// actual failures so the viewer can surface an error snackbar.
  final Future<Uint8List?> Function()? onShare;
  final String? shareFileName;

  const LetterHtmlViewerScreen({
    super.key,
    required this.title,
    required this.html,
    this.onGeneratePdf,
    this.onShare,
    this.shareFileName,
  });

  @override
  State<LetterHtmlViewerScreen> createState() => _LetterHtmlViewerScreenState();
}

class _LetterHtmlViewerScreenState extends State<LetterHtmlViewerScreen> {
  bool _isSharing = false;

  void _openInNewTab() {
    final bytes = Uint8List.fromList(utf8.encode(widget.html));
    final blob = web.Blob(
      [bytes.toJS].toJS,
      web.BlobPropertyBag(type: 'text/html'),
    );
    final url = web.URL.createObjectURL(blob);
    web.window.open(url, '_blank');
  }

  Future<void> _handleShare() async {
    if (widget.onShare == null) return;
    setState(() => _isSharing = true);
    try {
      final bytes = await widget.onShare!();
      if (bytes == null) return; // user cancelled a caller-side dialog
      final fileName = widget.shareFileName ?? 'letter.pdf';
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
    return Scaffold(
      backgroundColor: AppColors.bgPrimary,
      appBar: AppBar(
        backgroundColor: AppColors.bgSurface,
        title: Text(widget.title,
            style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary)),
        leading: IconButton(
          icon: Icon(Icons.arrow_back_rounded,
              size: 18, color: AppColors.textSecondary),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          if (widget.onGeneratePdf != null)
            IconButton(
              icon: Icon(Icons.picture_as_pdf_rounded,
                  size: 18, color: AppColors.textSecondary),
              tooltip: 'Generate PDF',
              onPressed: widget.onGeneratePdf,
            ),
          if (widget.onShare != null && canUseNativeShareControl())
            IconButton(
              icon: Icon(Icons.ios_share_rounded,
                  size: 18, color: AppColors.textSecondary),
              tooltip: 'Share',
              onPressed: _isSharing ? null : _handleShare,
            )
          else
            IconButton(
              icon: Icon(Icons.open_in_new_rounded,
                  size: 18, color: AppColors.textSecondary),
              tooltip: 'Open in new tab (for printing)',
              onPressed: _openInNewTab,
            ),
          const SizedBox(width: 4),
        ],
      ),
      body: HtmlBlobViewer(html: widget.html),
    );
  }
}
