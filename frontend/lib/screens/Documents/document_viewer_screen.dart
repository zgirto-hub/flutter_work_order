import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
import '../../theme/app_theme.dart';
import 'document_viewer_web.dart' if (dart.library.io) 'document_viewer_stub.dart';

class DocumentViewerScreen extends StatefulWidget {
  final String fileUrl;
  const DocumentViewerScreen({super.key, required this.fileUrl});

  @override
  State<DocumentViewerScreen> createState() => _DocumentViewerScreenState();
}

class _DocumentViewerScreenState extends State<DocumentViewerScreen> {
  _ViewState _state = _ViewState.loading;
  String? _errorMessage;
  Uint8List? _fileBytes;
  String? _textContent;
  String? _blobUrl;

  String get _ext => widget.fileUrl.split('?').first.split('.').last.toLowerCase();
  bool get _isImage => ['jpg', 'jpeg', 'png', 'gif', 'webp'].contains(_ext);
  bool get _isPdf => _ext == 'pdf';
  bool get _isTxt => _ext == 'txt';

  @override
  void initState() {
    super.initState();
    _loadFile();
  }

  Future<void> _loadFile() async {
    setState(() {
      _state = _ViewState.loading;
      _errorMessage = null;
      _fileBytes = null;
      _textContent = null;
      _blobUrl = null;
    });

    try {
      final response = await http
          .get(Uri.parse(widget.fileUrl))
          .timeout(const Duration(seconds: 30));

      if (!mounted) return;

      if (response.statusCode != 200) {
        setState(() {
          _state = _ViewState.error;
          _errorMessage = 'Server returned ${response.statusCode}';
        });
        return;
      }

      if (_isTxt) {
        setState(() { _textContent = response.body; _state = _ViewState.loaded; });
        return;
      }

      if (_isPdf && kIsWeb) {
        final url = createBlobUrl(response.bodyBytes, 'application/pdf');
        setState(() { _blobUrl = url; _state = _ViewState.loaded; });
        return;
      }

      setState(() { _fileBytes = response.bodyBytes; _state = _ViewState.loaded; });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _state = _ViewState.error;
        _errorMessage = e.toString().replaceAll('Exception: ', '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgPrimary,
      appBar: AppBar(
        backgroundColor: AppColors.bgSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, size: 20, color: AppColors.textSecondary),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(_shortName,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: AppColors.textPrimary)),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, size: 20, color: AppColors.textSecondary),
            onPressed: _loadFile,
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  String get _shortName {
    final name = widget.fileUrl.split('/').last.split('?').first;
    return name.length > 36 ? '${name.substring(0, 36)}…' : name;
  }

  Widget _buildBody() {
    switch (_state) {
      case _ViewState.loading:
        return _LoadingView(filename: _shortName);
      case _ViewState.error:
        return _ErrorView(message: _errorMessage ?? 'Unknown error', onRetry: _loadFile);
      case _ViewState.loaded:
        return _buildViewer();
    }
  }

  Widget _buildViewer() {
    if (_isPdf) {
      if (kIsWeb) {
        if (_blobUrl == null) return const _ErrorView(message: 'Could not create PDF preview');
        return PdfWebViewer(blobUrl: _blobUrl!);
      } else {
        if (_fileBytes == null) return const _ErrorView(message: 'Could not load PDF bytes');
        return SfPdfViewer.memory(_fileBytes!);
      }
    }

    if (_isTxt) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: SingleChildScrollView(
          child: SelectableText(
            _textContent ?? '',
            style: const TextStyle(fontSize: 13, color: AppColors.textPrimary, height: 1.7, fontFamily: 'monospace'),
          ),
        ),
      );
    }

    if (_isImage) {
      if (_fileBytes == null) return const _ErrorView(message: 'Could not load image');
      return Container(
        color: Colors.black,
        child: Center(
          child: InteractiveViewer(
            minScale: 0.3,
            maxScale: 8.0,
            child: Image.memory(_fileBytes!, fit: BoxFit.contain),
          ),
        ),
      );
    }

    return _UnsupportedView(ext: _ext);
  }
}

enum _ViewState { loading, loaded, error }

class _LoadingView extends StatelessWidget {
  final String filename;
  const _LoadingView({required this.filename});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(strokeWidth: 2.5, color: AppColors.accent),
          const SizedBox(height: 16),
          const Text('Loading file…', style: TextStyle(fontSize: 14, color: AppColors.textSecondary)),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: Text(filename,
                style: const TextStyle(fontSize: 11, color: AppColors.textTertiary),
                textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
    );
  }
}

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
              width: 56, height: 56,
              decoration: BoxDecoration(
                color: AppColors.dangerBg,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.dangerBorder, width: 0.5),
              ),
              child: const Icon(Icons.error_outline_rounded, size: 26, color: AppColors.dangerText),
            ),
            const SizedBox(height: 16),
            const Text('Could not load file',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
            const SizedBox(height: 6),
            Text(message,
                style: const TextStyle(fontSize: 12, color: AppColors.textTertiary),
                textAlign: TextAlign.center, maxLines: 4, overflow: TextOverflow.ellipsis),
            if (onRetry != null) ...[
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded, size: 16),
                label: const Text('Try again'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _UnsupportedView extends StatelessWidget {
  final String ext;
  const _UnsupportedView({required this.ext});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 36),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56, height: 56,
              decoration: BoxDecoration(color: AppColors.accentBg, borderRadius: BorderRadius.circular(16)),
              child: const Icon(Icons.insert_drive_file_outlined, size: 26, color: AppColors.accent),
            ),
            const SizedBox(height: 16),
            Text('.${ext.toUpperCase()} cannot be previewed',
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                textAlign: TextAlign.center),
            const SizedBox(height: 6),
            const Text('Use the Download button to open this file in an external app.',
                style: TextStyle(fontSize: 12, color: AppColors.textTertiary), textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}
