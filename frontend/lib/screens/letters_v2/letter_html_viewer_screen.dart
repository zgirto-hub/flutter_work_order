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

  // Pre-fetched PDF bytes for the share flow. We build these up-front in
  // initState (instead of on-demand when the share button is tapped) because
  // iOS Safari's Web Share API requires a live "transient user activation"
  // at the moment `navigator.share()` is called. Awaiting a multi-second
  // network fetch to the backend's WeasyPrint renderer inside the tap handler
  // blows past that activation window, `navigator.share()` throws
  // NotAllowedError, and the share sheet silently fails to open. The WO flow
  // works because PdfPreviewScreen caches its bytes during widget build for
  // the exact same reason.
  Uint8List? _prefetchedBytes;
  bool _prefetchInFlight = false;
  bool _prefetchFailed = false;

  @override
  void initState() {
    super.initState();
    if (widget.onShare != null) {
      _prefetchInFlight = true;
      widget.onShare!().then((bytes) {
        if (!mounted) return;
        setState(() {
          _prefetchedBytes = bytes;
          _prefetchInFlight = false;
        });
      }).catchError((Object e) {
        if (!mounted) return;
        setState(() {
          _prefetchInFlight = false;
          _prefetchFailed = true;
        });
      });
    }
  }

  void _openInNewTab() {
    // Open an empty window first, then write the HTML into it. The new tab
    // inherits the opener's origin, so path-absolute URLs inside the letter
    // HTML (e.g. `/api/letters-v2/assets/calibri.ttf`) resolve against the
    // Flutter app's backend origin instead of a null blob: context. That
    // keeps fonts and logos working for the "print from a new tab" flow
    // on desktop.
    final popup = web.window.open('', '_blank');
    if (popup == null) return; // popup blocked
    popup.document.open();
    popup.document.write(widget.html.toJS);
    popup.document.close();
  }

  Future<void> _handleShare() async {
    // Bytes must be pre-fetched — see initState. If they aren't ready yet
    // the button is disabled, so reaching this path means we have them.
    final bytes = _prefetchedBytes;
    if (bytes == null) return;
    setState(() => _isSharing = true);
    try {
      final fileName = widget.shareFileName ?? 'letter.pdf';
      // CRITICAL: no awaits between this line and the sharePdfBytes call,
      // so navigator.share() fires synchronously from the user gesture and
      // iOS keeps transient user activation live. This is what makes the
      // native share sheet open without leaving the PWA.
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

  Future<void> _retryPrefetch() async {
    if (widget.onShare == null) return;
    setState(() {
      _prefetchInFlight = true;
      _prefetchFailed = false;
    });
    try {
      final bytes = await widget.onShare!();
      if (!mounted) return;
      setState(() {
        _prefetchedBytes = bytes;
        _prefetchInFlight = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _prefetchInFlight = false;
        _prefetchFailed = true;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Couldn\'t load PDF for sharing')),
      );
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
              icon: _prefetchInFlight
                  ? SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 1.5,
                        color: AppColors.textSecondary,
                      ),
                    )
                  : Icon(
                      _prefetchFailed
                          ? Icons.refresh_rounded
                          : Icons.ios_share_rounded,
                      size: 18,
                      color: AppColors.textSecondary,
                    ),
              tooltip: _prefetchInFlight
                  ? 'Preparing PDF…'
                  : _prefetchFailed
                      ? 'Retry loading PDF'
                      : 'Share',
              onPressed: _isSharing || _prefetchInFlight
                  ? null
                  : (_prefetchFailed ? _retryPrefetch : _handleShare),
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
