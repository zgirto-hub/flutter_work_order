import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
import '../../theme/app_theme.dart';
import '../../services/download_helper.dart';
import 'package:work_order/services/platform_ua.dart';
import 'file_viewer_web.dart' if (dart.library.io) 'file_viewer_stub.dart';

class FileViewerScreen extends StatefulWidget {
  final String fileUrl;
  final String? fileName;

  const FileViewerScreen({
    super.key,
    required this.fileUrl,
    this.fileName,
  });

  @override
  State<FileViewerScreen> createState() => _FileViewerScreenState();
}

class _FileViewerScreenState extends State<FileViewerScreen> {
  _ViewState _state = _ViewState.loading;
  String? _errorMessage;
  Uint8List? _fileBytes;
  String? _textContent;
  String? _blobUrl;
  bool _downloading = false;
  double? _progress; // null = indeterminate, 0.0–1.0 = known progress

  final PdfViewerController _pdfController = PdfViewerController();

  bool get _isIosWeb => kIsWeb && PlatformUA.isIos;

  String get _ext =>
      widget.fileUrl.split('?').first.split('.').last.toLowerCase();
  bool get _isImage =>
      ['jpg', 'jpeg', 'png', 'gif', 'webp'].contains(_ext);
  bool get _isPdf => _ext == 'pdf';
  bool get _isTxt => _ext == 'txt';

  String get _displayName {
    if (widget.fileName != null && widget.fileName!.isNotEmpty) {
      return widget.fileName!;
    }
    final name = widget.fileUrl.split('/').last.split('?').first;
    return name.length > 40 ? '${name.substring(0, 40)}…' : name;
  }

  @override
  void initState() {
    super.initState();
    _loadFile();
  }

  @override
  void dispose() {
    _pdfController.dispose();
    super.dispose();
  }

  // ── Load ───────────────────────────────────────────────────────────────────

  Future<void> _loadFile() async {
    setState(() {
      _state = _ViewState.loading;
      _errorMessage = null;
      _fileBytes = null;
      _textContent = null;
      _blobUrl = null;
      _progress = null;
    });

    try {
      final client = http.Client();
      try {
        final streamedResponse = await client
            .send(http.Request('GET', Uri.parse(widget.fileUrl)))
            .timeout(const Duration(seconds: 30));

        if (!mounted) return;

        if (streamedResponse.statusCode != 200) {
          setState(() {
            _state = _ViewState.error;
            _errorMessage = 'Server returned ${streamedResponse.statusCode}';
          });
          return;
        }

        final totalBytes = streamedResponse.contentLength ?? 0;
        final chunks = <List<int>>[];
        var receivedBytes = 0;

        await for (final chunk in streamedResponse.stream) {
          chunks.add(chunk);
          receivedBytes += chunk.length;
          if (totalBytes > 0 && mounted) {
            setState(() => _progress = receivedBytes / totalBytes);
          }
        }

        if (!mounted) return;

        // Assemble all chunks into a single Uint8List
        final bodyBytes = Uint8List(receivedBytes);
        var offset = 0;
        for (final chunk in chunks) {
          bodyBytes.setRange(offset, offset + chunk.length, chunk);
          offset += chunk.length;
        }

        if (_isTxt) {
          setState(() {
            _textContent = utf8.decode(bodyBytes, allowMalformed: true);
            _state = _ViewState.loaded;
          });
          return;
        }

        if (_isPdf && kIsWeb) {
          if (_isIosWeb) {
            // iOS: PdfEmbedViewer uses the original URL (now cached); no blob needed
            setState(() => _state = _ViewState.loaded);
            return;
          }
          final url = createBlobUrl(bodyBytes, 'application/pdf');
          setState(() {
            _blobUrl = url;
            _state = _ViewState.loaded;
          });
          return;
        }

        setState(() {
          _fileBytes = bodyBytes;
          _state = _ViewState.loaded;
        });
      } finally {
        client.close();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _state = _ViewState.error;
        _errorMessage = e.toString().replaceAll('Exception: ', '');
      });
    }
  }

  // ── Download ───────────────────────────────────────────────────────────────

  Future<void> _triggerDownload() async {
    if (_downloading) return;
    setState(() => _downloading = true);
    try {
      await downloadFile(widget.fileUrl, _displayName);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Download failed: $e'),
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.dangerText,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ));
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgPrimary,
      appBar: _buildAppBar(),
      body: _buildBody(),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: AppColors.bgSurface,
      elevation: 0,
      scrolledUnderElevation: 0,
      leading: IconButton(
        icon: Icon(Icons.arrow_back_rounded,
            size: 20, color: AppColors.textSecondary),
        onPressed: () => Navigator.pop(context),
      ),
      title: Text(
        _displayName,
        style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: AppColors.textPrimary),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      actions: [
        if (_state == _ViewState.loaded || _state == _ViewState.error)
          IconButton(
            icon: Icon(Icons.refresh_rounded,
                size: 20, color: AppColors.textSecondary),
            onPressed: _loadFile,
            tooltip: 'Reload',
          ),
        // On mobile: share button in appbar
        if (_state == _ViewState.loaded && !kIsWeb)
          _downloading
              ? Padding(
                  padding: EdgeInsets.symmetric(horizontal: 14),
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 1.5,
                        color: AppColors.textSecondary),
                  ),
                )
              : IconButton(
                  icon: Icon(Icons.share_rounded,
                      size: 20, color: AppColors.textSecondary),
                  onPressed: _triggerDownload,
                  tooltip: 'Share / Save',
                ),
        SizedBox(width: 4),
      ],
    );
  }

  Widget _buildBody() {
    switch (_state) {
      case _ViewState.loading:
        return _LoadingView(filename: _displayName, progress: _progress);
      case _ViewState.error:
        return _ErrorView(
            message: _errorMessage ?? 'Unknown error', onRetry: _loadFile);
      case _ViewState.loaded:
        return _buildViewer();
    }
  }

  Widget _buildViewer() {
    if (_isPdf) return _buildPdfViewer();
    if (_isTxt) return _buildTextViewer();
    if (_isImage) return _buildImageViewer();
    return _UnsupportedView(ext: _ext, onDownload: _triggerDownload);
  }

  // ── PDF viewer ─────────────────────────────────────────────────────────────

  Widget _buildPdfViewer() {
    if (kIsWeb) {
      if (_isIosWeb) {
        // iOS web: <embed> with direct URL invokes native iOS PDF viewer (all pages)
        return Column(
          children: [
            Expanded(
              child: SizedBox.expand(
                child: PdfEmbedViewer(url: widget.fileUrl),
              ),
            ),
            _WebDownloadBar(
              fileName: _displayName,
              downloading: _downloading,
              onDownload: _triggerDownload,
            ),
          ],
        );
      }
      // Non-iOS web: iframe + blob URL
      if (_blobUrl == null) {
        return const _ErrorView(message: 'Could not create PDF preview');
      }
      return Column(
        children: [
          Expanded(
            child: SizedBox.expand(
              child: PdfWebViewer(blobUrl: _blobUrl!),
            ),
          ),
          _WebDownloadBar(
            fileName: _displayName,
            downloading: _downloading,
            onDownload: _triggerDownload,
          ),
        ],
      );
    }

    // Mobile / desktop: Syncfusion embedded viewer
    if (_fileBytes == null) {
      return const _ErrorView(message: 'Could not load PDF bytes');
    }
    return SfPdfViewer.memory(
      _fileBytes!,
      controller: _pdfController,
      canShowScrollHead: true,
      canShowScrollStatus: true,
      pageLayoutMode: PdfPageLayoutMode.continuous,
      onDocumentLoadFailed: (PdfDocumentLoadFailedDetails details) {
        if (mounted) {
          setState(() {
            _state = _ViewState.error;
            _errorMessage = details.description;
          });
        }
      },
    );
  }

  // ── Text viewer ────────────────────────────────────────────────────────────

  Widget _buildTextViewer() {
    return Column(
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: SingleChildScrollView(
              child: SelectableText(
                _textContent ?? '',
                style: TextStyle(
                  fontSize: 13,
                  color: AppColors.textPrimary,
                  height: 1.7,
                  fontFamily: 'monospace',
                ),
              ),
            ),
          ),
        ),
        if (kIsWeb)
          _WebDownloadBar(
            fileName: _displayName,
            downloading: _downloading,
            onDownload: _triggerDownload,
          ),
      ],
    );
  }

  // ── Image viewer ───────────────────────────────────────────────────────────

  Widget _buildImageViewer() {
    if (_fileBytes == null) {
      return const _ErrorView(message: 'Could not load image');
    }
    return Column(
      children: [
        Expanded(
          child: Container(
            color: Colors.black,
            child: Center(
              child: InteractiveViewer(
                minScale: 0.3,
                maxScale: 8.0,
                child: Image.memory(_fileBytes!, fit: BoxFit.contain),
              ),
            ),
          ),
        ),
        if (kIsWeb)
          _WebDownloadBar(
            fileName: _displayName,
            downloading: _downloading,
            onDownload: _triggerDownload,
          ),
      ],
    );
  }
}

// ── Web download bar ───────────────────────────────────────────────────────
// Shown at the bottom on web for all file types

class _WebDownloadBar extends StatelessWidget {
  final String fileName;
  final bool downloading;
  final VoidCallback onDownload;

  const _WebDownloadBar({
    required this.fileName,
    required this.downloading,
    required this.onDownload,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.bgSurface,
        border: Border(
          top: BorderSide(color: AppColors.border, width: 0.5),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            // File icon
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: AppColors.accentBg,
                borderRadius: BorderRadius.circular(9),
              ),
              child: Icon(Icons.insert_drive_file_outlined,
                  size: 17, color: AppColors.accent),
            ),
            SizedBox(width: 10),
            // File name
            Expanded(
              child: Text(
                fileName,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textPrimary,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            SizedBox(width: 10),
            // Download button
            SizedBox(
              height: 36,
              child: ElevatedButton.icon(
                onPressed: downloading ? null : onDownload,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.accent,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 0),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(9)),
                  textStyle: TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w600),
                ),
                icon: downloading
                    ? SizedBox(
                        width: 13,
                        height: 13,
                        child: CircularProgressIndicator(
                            strokeWidth: 1.5, color: Colors.white),
                      )
                    : Icon(Icons.download_rounded, size: 15),
                label: Text(downloading ? 'Opening…' : 'Download'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── State ──────────────────────────────────────────────────────────────────

enum _ViewState { loading, loaded, error }

// ── Loading view ───────────────────────────────────────────────────────────

class _LoadingView extends StatefulWidget {
  final String filename;
  final double? progress;
  const _LoadingView({required this.filename, this.progress});

  @override
  State<_LoadingView> createState() => _LoadingViewState();
}

class _LoadingViewState extends State<_LoadingView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final List<Animation<double>> _dots;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();

    _dots = [0.0, 0.33, 0.66].map((offset) {
      return CurvedAnimation(
        parent: _ctrl,
        curve: Interval(offset, offset + 0.34, curve: Curves.easeInOut),
      );
    }).toList();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pct = widget.progress;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: _dots.map((anim) {
              return AnimatedBuilder(
                animation: anim,
                builder: (_, __) => Container(
                  width: 8,
                  height: 8,
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.accent.withValues(
                      alpha: 0.2 + 0.8 * anim.value,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          SizedBox(height: 16),
          Text(
            pct != null
                ? 'Loading… ${(pct * 100).toStringAsFixed(0)}%'
                : 'Loading file…',
            style: TextStyle(
                fontSize: 14, color: AppColors.textSecondary),
          ),
          SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: Text(widget.filename,
                style: TextStyle(
                    fontSize: 11, color: AppColors.textTertiary),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
    );
  }
}

// ── Error view ─────────────────────────────────────────────────────────────

class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback? onRetry;
  const _ErrorView({required this.message, this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 36),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: AppColors.dangerBg,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                    color: AppColors.dangerBorder, width: 0.5),
              ),
              child: Icon(Icons.error_outline_rounded,
                  size: 26, color: AppColors.dangerText),
            ),
            SizedBox(height: 16),
            Text('Could not load file',
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary)),
            SizedBox(height: 6),
            Text(message,
                style: TextStyle(
                    fontSize: 12, color: AppColors.textTertiary),
                textAlign: TextAlign.center,
                maxLines: 4,
                overflow: TextOverflow.ellipsis),
            if (onRetry != null) ...[
              SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: onRetry,
                icon: Icon(Icons.refresh_rounded, size: 16),
                label: Text('Try again'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Unsupported file view ──────────────────────────────────────────────────

class _UnsupportedView extends StatelessWidget {
  final String ext;
  final VoidCallback onDownload;
  const _UnsupportedView(
      {required this.ext, required this.onDownload});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 36),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: AppColors.accentBg,
                borderRadius: BorderRadius.circular(18),
              ),
              child: Icon(Icons.insert_drive_file_outlined,
                  size: 30, color: AppColors.accent),
            ),
            SizedBox(height: 16),
            Text('.${ext.toUpperCase()} cannot be previewed',
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary),
                textAlign: TextAlign.center),
            SizedBox(height: 8),
            Text(
              'Use the button below to open in an external app.',
              style: TextStyle(
                  fontSize: 12, color: AppColors.textTertiary),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: onDownload,
              icon: Icon(Icons.download_rounded, size: 16),
              label: Text('Download / Open'),
            ),
          ],
        ),
      ),
    );
  }
}
