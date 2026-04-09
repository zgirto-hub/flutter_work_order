import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:js_interop';
import 'dart:ui_web' as ui_web;
import 'package:web/web.dart' as web;
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:printing/printing.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../config.dart';
import '../../models/generated_letter.dart';
import '../../services/letter_service.dart';
import '../../services/payment_certificate_service.dart';
import '../../services/pdf/payment_certificate_pdf_service.dart';
import '../../widgets/ai_document_expert_widget.dart';
import 'widgets/payment_cert_picker.dart';

/// Letter form with WYSIWYG rich text editor (v2 — WeasyPrint backend).
class LetterFormTabV2 extends StatefulWidget {
  final VoidCallback onLetterSaved;
  final GeneratedLetter? editLetter;

  const LetterFormTabV2(
      {super.key, required this.onLetterSaved, this.editLetter});

  @override
  State<LetterFormTabV2> createState() => _LetterFormTabV2State();
}

class _LetterFormTabV2State extends State<LetterFormTabV2> {
  final _formKey = GlobalKey<FormState>();
  final _isharaCtrl = TextEditingController();
  final _alsayedCtrl = TextEditingController();
  final _almawdooCtrl = TextEditingController();
  final _signerTitleCtrl = TextEditingController();
  final _alasmCtrl = TextEditingController();
  final _ccListCtrl = TextEditingController();
  final _ccNameCtrl = TextEditingController();
  final List<String> _ccNames = [];

  DateTime? _selectedDate;

  Uint8List? _signatureBytes;
  String? _signatureBase64;
  bool _replyRequired = false;
  bool _isLoading = false;
  bool _hasPreviewedOnce = false;
  double _editorHeight = 500;

  // PDF styling options
  double _refFontSize = 11;
  bool _refBold = false;
  bool _refUnderline = false;
  double _recipientFontSize = 12;
  bool _recipientBold = false;
  bool _recipientUnderline = false;
  double _subjectFontSize = 13;
  bool _subjectBold = true;
  bool _subjectUnderline = true;
  double _dateFontSize = 11;
  bool _dateBold = false;
  bool _dateUnderline = false;
  String? _editingLetterId;
  String? _initialBodyHtml;

  // Attachments
  final List<_Attachment> _attachments = [];
  List<LinkedPaymentCertificate> _linkedCerts = [];
  int _imageCount = 0;

  // Unique ID for the HTML editor iframe
  late final String _editorViewType;
  web.HTMLIFrameElement? _editorIframe;
  Completer<String>? _htmlCompleter;
  StreamSubscription? _messageSub;

  @override
  void initState() {
    super.initState();
    _editorViewType = 'rich-editor-${DateTime.now().millisecondsSinceEpoch}';
    final letter = widget.editLetter;
    if (letter != null) {
      _editingLetterId = letter.id;
      _isharaCtrl.text = letter.ishara;
      _alsayedCtrl.text = letter.alsayed;
      _almawdooCtrl.text = letter.almawdoo;
      _signerTitleCtrl.text = letter.signerTitle;
      _alasmCtrl.text = letter.alasm;
      _initialBodyHtml = letter.bodyText;
      _linkedCerts = List.from(letter.paymentCertificates);
      // Restore CC names
      if (letter.ccList != null && letter.ccList!.isNotEmpty) {
        _ccNames.addAll(
            letter.ccList!.split('\n').where((n) => n.trim().isNotEmpty));
      }
      // Restore date — tarikh could be YYYY-MM-DD or DD/MM/YYYY
      if (letter.tarikh.isNotEmpty) {
        try {
          if (letter.tarikh.contains('-')) {
            _selectedDate = DateTime.parse(letter.tarikh);
          } else if (letter.tarikh.contains('/')) {
            final parts = letter.tarikh.split('/');
            _selectedDate = DateTime(
                int.parse(parts[2]), int.parse(parts[1]), int.parse(parts[0]));
          }
        } catch (_) {}
      }
      if (letter.signatureBase64 != null &&
          letter.signatureBase64!.isNotEmpty) {
        _signatureBase64 = letter.signatureBase64;
        try {
          String b64 = letter.signatureBase64!;
          if (b64.contains(',')) b64 = b64.split(',').last;
          _signatureBytes = base64Decode(b64);
        } catch (_) {}
      }
      // Restore formatting state
      _refFontSize = letter.refFontSize;
      _refBold = letter.refBold;
      _refUnderline = letter.refUnderline;
      _dateFontSize = letter.tarikhFontSize;
      _dateBold = letter.tarikhBold;
      _dateUnderline = letter.tarikhUnderline;
      _recipientFontSize = letter.recipientFontSize;
      _recipientBold = letter.recipientBold;
      _recipientUnderline = letter.recipientUnderline;
      _subjectFontSize = letter.subjectFontSize;
      _subjectBold = letter.subjectBold;
      _subjectUnderline = letter.subjectUnderline;
    }
    _registerEditor();
    _listenForMessages();
  }

  void _registerEditor() {
    final iframe = web.HTMLIFrameElement()
      ..style.setProperty('border', 'none')
      ..style.setProperty('width', '100%')
      ..style.setProperty('height', '100%');
    iframe.setAttribute('srcdoc', _editorHtml);
    _editorIframe = iframe;

    ui_web.platformViewRegistry.registerViewFactory(
      _editorViewType,
      (int viewId) => iframe,
    );
  }

  void _listenForMessages() {
    _messageSub = web.EventStreamProviders.messageEvent
        .forTarget(web.window)
        .listen((web.MessageEvent event) {
      final data = event.data;
      if (data == null) return;
      final str = (data as JSString).toDart;
      if (str.startsWith('EDITOR_HTML:')) {
        final html = str.substring('EDITOR_HTML:'.length);
        _htmlCompleter?.complete(html);
        _htmlCompleter = null;
      } else if (str == 'EDITOR_READY' && _initialBodyHtml != null) {
        // Editor iframe loaded — inject the initial HTML for editing
        final cw = _editorIframe?.contentWindow;
        cw?.postMessage('SET_HTML:$_initialBodyHtml'.toJS, '*'.toJS);
        _initialBodyHtml = null;
      } else if (str == 'INSERT_IMAGE_REQUEST') {
        _uploadImage();
      }
    });
  }

  /// Request the rich HTML content from the editor iframe via postMessage.
  Future<String> _getEditorHtml() async {
    final cw = _editorIframe?.contentWindow;
    if (cw == null) return '';
    _htmlCompleter = Completer<String>();
    cw.postMessage('GET_HTML'.toJS, '*'.toJS);
    return _htmlCompleter!.future.timeout(
      const Duration(seconds: 2),
      onTimeout: () => '',
    );
  }

  /// Inject HTML content into the editor iframe via postMessage.
  void _setEditorHtml(String html) {
    final cw = _editorIframe?.contentWindow;
    if (cw == null) return;
    cw.postMessage('SET_HTML:$html'.toJS, '*'.toJS);
  }

  Future<void> _pickAttachments() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      withData: true,
      type: FileType.any,
    );
    if (result == null || result.files.isEmpty) return;
    for (final file in result.files) {
      if (file.bytes == null) continue;
      if (file.bytes!.lengthInBytes > 10 * 1024 * 1024) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('${file.name}: File exceeds 10MB limit')),
          );
        }
        continue;
      }
      final isImage = ['png', 'jpg', 'jpeg', 'gif', 'webp']
          .contains(file.extension?.toLowerCase());
      setState(() {
        _attachments.add(_Attachment(
          name: file.name,
          bytes: file.bytes!,
          base64: base64Encode(file.bytes!),
          isImage: isImage,
        ));
      });
    }
  }

  Future<void> _pickSignature() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: false,
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    if (file.bytes == null) return;
    if (file.bytes!.lengthInBytes > 5 * 1024 * 1024) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('File exceeds 5MB limit')),
        );
      }
      return;
    }
    setState(() {
      _signatureBytes = file.bytes;
      _signatureBase64 = base64Encode(file.bytes!);
    });
  }

  Future<void> _uploadImage() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['png', 'jpg', 'jpeg', 'gif', 'webp'],
      allowMultiple: false,
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    if (file.bytes == null) return;
    if (file.bytes!.lengthInBytes > 5 * 1024 * 1024) {
      _editorIframe?.contentWindow?.postMessage(
        'INSERT_IMAGE_ERROR:File exceeds 5MB limit. Please choose a smaller image.'
            .toJS,
        '*'.toJS,
      );
      return;
    }
    _imageCount++;
    if (_imageCount > 10) {
      final proceed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Image Limit Warning'),
          content: const Text(
            'This letter already has more than 10 images. '
            'Adding more may affect performance. Continue?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Continue'),
            ),
          ],
        ),
      );
      if (proceed != true) {
        _imageCount--;
        return;
      }
    }
    _editorIframe?.contentWindow?.postMessage(
      'INSERT_IMAGE_LOADING'.toJS,
      '*'.toJS,
    );
    try {
      final url = await LetterService().uploadImage(file.bytes!, file.name);
      final fullUrl = '${AppConfig.downloadUrl}$url';
      _editorIframe?.contentWindow?.postMessage(
        'INSERT_IMAGE:$fullUrl'.toJS,
        '*'.toJS,
      );
    } catch (e) {
      _editorIframe?.contentWindow?.postMessage(
        'REMOVE_IMAGE_LOADING'.toJS,
        '*'.toJS,
      );
      _editorIframe?.contentWindow?.postMessage(
        'INSERT_IMAGE_ERROR:${e.toString()}'.toJS,
        '*'.toJS,
      );
    }
  }

  Future<void> _showPreview() async {
    if (!_formKey.currentState!.validate()) return;
    final bodyHtml = await _getEditorHtml();
    if (bodyHtml.trim().isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter the letter body')),
      );
      return;
    }

    setState(() => _hasPreviewedOnce = true);

    if (!mounted) return;

    // Call backend preview-html endpoint to get the exact HTML that WeasyPrint will render
    String? previewHtml;
    try {
      final body = {
        'ishara': _isharaCtrl.text,
        'tarikh': _selectedDate != null
            ? '${_selectedDate!.day.toString().padLeft(2, '0')}/${_selectedDate!.month.toString().padLeft(2, '0')}/${_selectedDate!.year}'
            : '',
        'alsayed': _alsayedCtrl.text,
        'almawdoo': _almawdooCtrl.text,
        'body_html': bodyHtml,
        'signer_title': _signerTitleCtrl.text,
        'alasm': _alasmCtrl.text,
        'signature_base64': _signatureBase64,
        'reply_required': _replyRequired,
        'cc_list': _ccNames.isEmpty ? null : _ccNames.join('\n'),
        'ref_font_size': _refFontSize,
        'ref_bold': _refBold,
        'ref_underline': _refUnderline,
        'tarikh_font_size': _dateFontSize,
        'tarikh_bold': _dateBold,
        'tarikh_underline': _dateUnderline,
        'recipient_font_size': _recipientFontSize,
        'recipient_bold': _recipientBold,
        'recipient_underline': _recipientUnderline,
        'subject_font_size': _subjectFontSize,
        'subject_bold': _subjectBold,
        'subject_underline': _subjectUnderline,
        'created_by_email': '',
      };
      final uri = Uri.parse('${AppConfig.baseUrl}/letters-v2/preview-html');
      final res = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(body),
      );
      if (res.statusCode == 200) {
        previewHtml = res.body;
      }
    } catch (_) {}

    if (!mounted) return;
    if (previewHtml == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to load preview')),
      );
      return;
    }

    // Register a unique iframe to show the preview HTML
    final previewId = 'preview-${DateTime.now().millisecondsSinceEpoch}';
    final previewIframe = web.HTMLIFrameElement()
      ..style.setProperty('border', 'none')
      ..style.setProperty('width', '100%')
      ..style.setProperty('height', '100%')
      ..style.setProperty('background', '#fff');
    previewIframe.setAttribute('srcdoc', previewHtml);

    ui_web.platformViewRegistry.registerViewFactory(
      previewId,
      (int viewId) => previewIframe,
    );

    if (!mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.all(16),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 750, maxHeight: 950),
          child: Column(
            children: [
              // Dialog header
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(ctx).colorScheme.primary,
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(12)),
                ),
                child: Row(
                  children: [
                    const Text(
                      'Letter Preview',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
              ),
              // Preview: actual HTML rendered in iframe (same as PDF)
              Expanded(
                child: HtmlElementView(viewType: previewId),
              ),
              // Actions
              Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('Close'),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      onPressed: () {
                        Navigator.pop(ctx);
                        _generatePdf();
                      },
                      icon: const Icon(Icons.picture_as_pdf),
                      label: const Text('Generate PDF'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFCC0000),
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _generatePdf() async {
    if (!_formKey.currentState!.validate()) return;
    final bodyHtml = await _getEditorHtml();
    if (bodyHtml.trim().isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter the letter body')),
      );
      return;
    }

    setState(() => _isLoading = true);
    try {
      final body = {
        'ishara': _isharaCtrl.text,
        'tarikh': _selectedDate != null
            ? '${_selectedDate!.day.toString().padLeft(2, '0')}/${_selectedDate!.month.toString().padLeft(2, '0')}/${_selectedDate!.year}'
            : '',
        'alsayed': _alsayedCtrl.text,
        'almawdoo': _almawdooCtrl.text,
        'body_html': bodyHtml,
        'signer_title': _signerTitleCtrl.text,
        'alasm': _alasmCtrl.text,
        'signature_base64': _signatureBase64,
        'reply_required': _replyRequired,
        'cc_list': _ccNames.isEmpty ? null : _ccNames.join('\n'),
        'ref_font_size': _refFontSize,
        'ref_bold': _refBold,
        'ref_underline': _refUnderline,
        'tarikh_font_size': _dateFontSize,
        'tarikh_bold': _dateBold,
        'tarikh_underline': _dateUnderline,
        'recipient_font_size': _recipientFontSize,
        'recipient_bold': _recipientBold,
        'recipient_underline': _recipientUnderline,
        'subject_font_size': _subjectFontSize,
        'subject_bold': _subjectBold,
        'subject_underline': _subjectUnderline,
        'attachments': _attachments
            .map((_Attachment a) => <String, dynamic>{
                  'name': a.name,
                  'data': a.base64,
                  'is_image': a.isImage,
                })
            .toList(),
      };

      Uint8List pdfBytes = Uint8List(0);
      try {
        if (_editingLetterId != null) {
          pdfBytes = await LetterService().updateV2(
            _editingLetterId!,
            body,
            paymentCertificateIds: _linkedCerts.map((c) => c.id).toList(),
          );
        } else {
          pdfBytes = await LetterService().generateV2(
            body,
            paymentCertificateIds: _linkedCerts.map((c) => c.id).toList(),
          );
        }
      } on CertificatesAlreadyLinkedException catch (e) {
        if (!mounted) return;
        final confirm = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Reassign payment certificate?'),
            content: Text(
              'This certificate is already linked to another letter. Reassign it?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Reassign'),
              ),
            ],
          ),
        );
        if (confirm != true) return;
        if (_editingLetterId != null) {
          pdfBytes = await LetterService().updateV2(
            _editingLetterId!,
            body,
            paymentCertificateIds: _linkedCerts.map((c) => c.id).toList(),
            forceReassign: true,
          );
        } else {
          pdfBytes = await LetterService().generateV2(
            body,
            paymentCertificateIds: _linkedCerts.map((c) => c.id).toList(),
            forceReassign: true,
          );
        }
      }
      await Printing.sharePdf(
        bytes: pdfBytes,
        filename: 'letter_${DateTime.now().millisecondsSinceEpoch}.pdf',
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(_editingLetterId != null
                  ? 'Letter updated successfully'
                  : 'Letter generated successfully')),
        );
      }
      if (_editingLetterId == null) {
        widget.onLetterSaved();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _exportCombinedPdf() async {
    if (_editingLetterId == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please save the letter first')),
        );
      }
      return;
    }

    setState(() => _isLoading = true);
    try {
      final bodyHtml = await _getEditorHtml();
      final body = {
        'ishara': _isharaCtrl.text,
        'tarikh': _selectedDate != null
            ? '${_selectedDate!.day.toString().padLeft(2, '0')}/${_selectedDate!.month.toString().padLeft(2, '0')}/${_selectedDate!.year}'
            : '',
        'alsayed': _alsayedCtrl.text,
        'almawdoo': _almawdooCtrl.text,
        'body_html': bodyHtml,
        'signer_title': _signerTitleCtrl.text,
        'alasm': _alasmCtrl.text,
        'signature_base64': _signatureBase64,
        'reply_required': _replyRequired,
        'cc_list': _ccNames.isEmpty ? null : _ccNames.join('\n'),
        'ref_font_size': _refFontSize,
        'ref_bold': _refBold,
        'ref_underline': _refUnderline,
        'tarikh_font_size': _dateFontSize,
        'tarikh_bold': _dateBold,
        'tarikh_underline': _dateUnderline,
        'recipient_font_size': _recipientFontSize,
        'recipient_bold': _recipientBold,
        'recipient_underline': _recipientUnderline,
        'subject_font_size': _subjectFontSize,
        'subject_bold': _subjectBold,
        'subject_underline': _subjectUnderline,
        'created_by_email':
            Supabase.instance.client.auth.currentUser?.email ?? '',
      };

      final Map<String, Uint8List> certPdfs = {};
      for (final cert in _linkedCerts) {
        final fullCert = await PaymentCertificateService().getById(cert.id);
        if (fullCert != null) {
          final pdfBytes = await PaymentCertificatePdfService.build(fullCert);
          certPdfs[cert.id] = pdfBytes;
        }
      }

      final requesterEmail =
          Supabase.instance.client.auth.currentUser?.email ?? '';
      final mergedPdf = await LetterService().exportLetterWithAttachments(
        letterId: _editingLetterId!,
        letterBody: body,
        orderedCertIds: _linkedCerts.map((c) => c.id).toList(),
        certPdfs: certPdfs,
        requesterEmail: requesterEmail,
      );

      if (mounted) {
        await Printing.sharePdf(
          bytes: mergedPdf,
          filename:
              'letter_${DateTime.now().millisecondsSinceEpoch}_combined.pdf',
        );
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Combined PDF exported successfully')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error exporting combined PDF: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _messageSub?.cancel();
    _isharaCtrl.dispose();
    _alsayedCtrl.dispose();
    _almawdooCtrl.dispose();
    _signerTitleCtrl.dispose();
    _alasmCtrl.dispose();
    _ccListCtrl.dispose();
    _ccNameCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Reference Number + Date (same row) ──
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Reference Number
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildLabel('Reference Number'),
                      SizedBox(
                        width: 180,
                        child: TextFormField(
                          controller: _isharaCtrl,
                          decoration: _inputDecor('e.g. 2026-23279'),
                          textAlign: TextAlign.right,
                          validator: (v) =>
                              (v == null || v.isEmpty) ? 'Required' : null,
                        ),
                      ),
                      _buildStyleRow(
                        fontSize: _refFontSize,
                        bold: _refBold,
                        underline: _refUnderline,
                        onFontSizeChanged: (v) =>
                            setState(() => _refFontSize = v),
                        onBoldChanged: (v) => setState(() => _refBold = v),
                        onUnderlineChanged: (v) =>
                            setState(() => _refUnderline = v),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                // Date
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildLabel('Date'),
                      SizedBox(
                        width: 180,
                        child: InkWell(
                          onTap: () async {
                            final date = await showDatePicker(
                              context: context,
                              initialDate: _selectedDate ?? DateTime.now(),
                              firstDate: DateTime(2020),
                              lastDate: DateTime(2100),
                            );
                            if (date != null)
                              setState(() => _selectedDate = date);
                          },
                          child: InputDecorator(
                            decoration: _inputDecor('Select date'),
                            child: Text(
                              _selectedDate != null
                                  ? '${_selectedDate!.day.toString().padLeft(2, '0')}/${_selectedDate!.month.toString().padLeft(2, '0')}/${_selectedDate!.year}'
                                  : '',
                              textAlign: TextAlign.right,
                            ),
                          ),
                        ),
                      ),
                      _buildStyleRow(
                        fontSize: _dateFontSize,
                        bold: _dateBold,
                        underline: _dateUnderline,
                        onFontSizeChanged: (v) =>
                            setState(() => _dateFontSize = v),
                        onBoldChanged: (v) => setState(() => _dateBold = v),
                        onUnderlineChanged: (v) =>
                            setState(() => _dateUnderline = v),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // ── Recipient (السيد) ──
            _buildLabel('Recipient'),
            TextFormField(
              controller: _alsayedCtrl,
              decoration: _inputDecor('Recipient name and title'),
              validator: (v) => (v == null || v.isEmpty) ? 'Required' : null,
            ),
            _buildStyleRow(
              fontSize: _recipientFontSize,
              bold: _recipientBold,
              underline: _recipientUnderline,
              onFontSizeChanged: (v) => setState(() => _recipientFontSize = v),
              onBoldChanged: (v) => setState(() => _recipientBold = v),
              onUnderlineChanged: (v) =>
                  setState(() => _recipientUnderline = v),
            ),
            const Padding(
              padding: EdgeInsets.only(top: 4, right: 8),
              child: Text('المحترم',
                  style: TextStyle(fontSize: 13, color: Colors.grey)),
            ),
            const SizedBox(height: 16),

            // ── Subject (الموضوع) ──
            _buildLabel('Subject'),
            TextFormField(
              controller: _almawdooCtrl,
              decoration: _inputDecor('Letter subject'),
              maxLines: 3,
              minLines: 2,
              validator: (v) => (v == null || v.isEmpty) ? 'Required' : null,
            ),
            _buildStyleRow(
              fontSize: _subjectFontSize,
              bold: _subjectBold,
              onFontSizeChanged: (v) => setState(() => _subjectFontSize = v),
              onBoldChanged: (v) => setState(() => _subjectBold = v),
              underline: _subjectUnderline,
              onUnderlineChanged: (v) => setState(() => _subjectUnderline = v),
            ),
            const SizedBox(height: 16),

            // ── Rich Text Editor (Body) ──
            _buildLabel('Letter Body'),
            Column(
              children: [
                Container(
                  height: _editorHeight,
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey.shade400),
                    borderRadius:
                        const BorderRadius.vertical(top: Radius.circular(8)),
                  ),
                  clipBehavior: Clip.hardEdge,
                  child: HtmlElementView(viewType: _editorViewType),
                ),
                GestureDetector(
                  onVerticalDragUpdate: (details) {
                    setState(() {
                      _editorHeight =
                          (_editorHeight + details.delta.dy).clamp(200, 1200);
                    });
                  },
                  child: Container(
                    height: 18,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade200,
                      borderRadius: const BorderRadius.vertical(
                          bottom: Radius.circular(8)),
                      border: Border.all(color: Colors.grey.shade400),
                    ),
                    child: Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.grey.shade500,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            AiDocumentExpertWidget(
              onGetHtml: _getEditorHtml,
              onApplyHtml: _setEditorHtml,
            ),
            const SizedBox(height: 16),

            // ── Signer Title ──
            _buildLabel('Signer Title'),
            TextFormField(
              controller: _signerTitleCtrl,
              decoration: _inputDecor('e.g. مدير عام، رئيس قسم'),
            ),
            const SizedBox(height: 16),

            // ── Signer (الاسم) ──
            _buildLabel('Signer Name'),
            TextFormField(
              controller: _alasmCtrl,
              decoration: _inputDecor('Signer name'),
              validator: (v) => (v == null || v.isEmpty) ? 'Required' : null,
            ),
            const SizedBox(height: 16),

            // ── Reply Required (مطلوب الرد) ──
            Row(
              children: [
                Checkbox(
                  value: _replyRequired,
                  onChanged: (v) => setState(() => _replyRequired = v ?? false),
                ),
                const Text('Reply Required', style: TextStyle(fontSize: 14)),
              ],
            ),
            const SizedBox(height: 12),

            // ── CC List (نسخة الى) ──
            _buildLabel('CC List'),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _ccNameCtrl,
                    decoration: InputDecoration(
                      hintText: 'Add CC name',
                      border: const OutlineInputBorder(),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.add_circle,
                            color: Color(0xFFCC0000)),
                        onPressed: () {
                          final name = _ccNameCtrl.text.trim();
                          if (name.isNotEmpty) {
                            setState(() {
                              _ccNames.add(name);
                              _ccNameCtrl.clear();
                            });
                          }
                        },
                      ),
                    ),
                    onFieldSubmitted: (value) {
                      final name = value.trim();
                      if (name.isNotEmpty) {
                        setState(() {
                          _ccNames.add(name);
                          _ccNameCtrl.clear();
                        });
                      }
                    },
                  ),
                ),
              ],
            ),
            if (_ccNames.isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade300),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade700,
                        borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(5)),
                      ),
                      child: const Row(
                        children: [
                          Expanded(
                              child: Text('CC',
                                  style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13))),
                          Text('Delete',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13)),
                        ],
                      ),
                    ),
                    ..._ccNames.asMap().entries.map((entry) {
                      final i = entry.key;
                      final name = entry.value;
                      return Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          border: Border(
                              bottom: BorderSide(color: Colors.grey.shade200)),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                                child: Text(name,
                                    style: const TextStyle(fontSize: 13))),
                            IconButton(
                              icon: const Icon(Icons.delete_outline,
                                  color: Colors.red, size: 20),
                              onPressed: () =>
                                  setState(() => _ccNames.removeAt(i)),
                              constraints: const BoxConstraints(),
                              padding: EdgeInsets.zero,
                            ),
                          ],
                        ),
                      );
                    }),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 16),

            // ── Attachments (المرفقات) ──
            _buildLabel('Attachments'),
            if (_attachments.isNotEmpty)
              ..._attachments.asMap().entries.map((entry) {
                final i = entry.key;
                final att = entry.value;
                return Card(
                  margin: const EdgeInsets.only(bottom: 6),
                  child: ListTile(
                    leading: att.isImage
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: Image.memory(att.bytes,
                                width: 40, height: 40, fit: BoxFit.cover),
                          )
                        : const Icon(Icons.attach_file),
                    title: Text(att.name, style: const TextStyle(fontSize: 13)),
                    subtitle: Text(
                        '${(att.bytes.lengthInBytes / 1024).toStringAsFixed(0)} KB',
                        style: const TextStyle(fontSize: 11)),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline,
                          color: Colors.red, size: 20),
                      onPressed: () => setState(() => _attachments.removeAt(i)),
                    ),
                    dense: true,
                  ),
                );
              }),
            OutlinedButton.icon(
              onPressed: _pickAttachments,
              icon: const Icon(Icons.attach_file),
              label: const Text('Add Attachment'),
            ),
            const SizedBox(height: 16),

            // ── Payment Certificate Attachments ──
            _buildLabel('Payment Certificates'),
            if (_linkedCerts.isNotEmpty)
              SizedBox(
                height: 150,
                child: ReorderableListView.builder(
                  shrinkWrap: true,
                  itemCount: _linkedCerts.length,
                  onReorder: (oldIndex, newIndex) {
                    setState(() {
                      if (newIndex > oldIndex) newIndex--;
                      final item = _linkedCerts.removeAt(oldIndex);
                      _linkedCerts.insert(newIndex, item);
                    });
                  },
                  itemBuilder: (context, index) {
                    final cert = _linkedCerts[index];
                    return Card(
                      key: ValueKey(cert.id),
                      margin: const EdgeInsets.only(bottom: 6),
                      child: ListTile(
                        leading: const Icon(Icons.description),
                        title: Text(cert.certificateNumber,
                            style: const TextStyle(fontSize: 13)),
                        subtitle: Text(cert.subject,
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.delete_outline,
                                  color: Colors.red, size: 20),
                              onPressed: () =>
                                  setState(() => _linkedCerts.removeAt(index)),
                            ),
                            const Icon(Icons.drag_handle),
                          ],
                        ),
                        dense: true,
                      ),
                    );
                  },
                ),
              ),
            OutlinedButton.icon(
              onPressed: () async {
                final selected = await PaymentCertPicker.show(
                  context,
                  alreadySelectedIds: _linkedCerts.map((c) => c.id).toList(),
                );
                if (selected != null && selected.isNotEmpty) {
                  setState(() {
                    for (int i = 0; i < selected.length; i++) {
                      _linkedCerts.add(LinkedPaymentCertificate(
                        id: selected[i].id,
                        certificateNumber: selected[i].certificateNumber,
                        subject: selected[i].subject,
                        letterLinkOrder: _linkedCerts.length + i,
                      ));
                    }
                  });
                }
              },
              icon: const Icon(Icons.add),
              label: const Text('Add Payment Certificate'),
            ),
            const SizedBox(height: 16),

            // ── Signature Upload (التوقيع الإلكتروني) ──
            _buildLabel('Electronic Signature'),
            if (_signatureBytes != null)
              Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: Image.memory(_signatureBytes!, height: 70),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.delete_outline, color: Colors.red),
                    onPressed: () => setState(() {
                      _signatureBytes = null;
                      _signatureBase64 = null;
                    }),
                  ),
                ],
              )
            else
              OutlinedButton.icon(
                onPressed: _pickSignature,
                icon: const Icon(Icons.upload_file),
                label: const Text('Upload Signature'),
              ),
            const SizedBox(height: 24),

            // ── Action Buttons ──
            Row(
              children: [
                OutlinedButton(
                  onPressed: () => Navigator.of(context).maybePop(),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 24, vertical: 14),
                  ),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: 12),
                ElevatedButton(
                  onPressed: _isLoading ? null : _showPreview,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFCC0000),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 24, vertical: 14),
                  ),
                  child: const Text('Preview'),
                ),
                const SizedBox(width: 12),
                ElevatedButton.icon(
                  onPressed: ((_hasPreviewedOnce || _editingLetterId != null) &&
                          !_isLoading)
                      ? _generatePdf
                      : null,
                  icon: _isLoading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Icon(_editingLetterId != null
                          ? Icons.save
                          : Icons.picture_as_pdf),
                  label: Text(_editingLetterId != null
                      ? 'Save Changes'
                      : 'Generate PDF'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFCC0000),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 24, vertical: 14),
                    disabledBackgroundColor: Colors.grey.shade400,
                  ),
                ),
              ],
            ),
            if (_linkedCerts.isNotEmpty) ...[
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _linkedCerts.isEmpty ? null : _exportCombinedPdf,
                icon: const Icon(Icons.picture_as_pdf),
                label: const Text('Export Combined PDF'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                ),
              ),
            ],
            if (!_hasPreviewedOnce && _editingLetterId == null)
              const Padding(
                padding: EdgeInsets.only(top: 6),
                child: Text(
                  'Preview required before generating',
                  style: TextStyle(fontSize: 11, color: Colors.orange),
                ),
              ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildLabel(String text, {bool big = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        text,
        style: TextStyle(
          fontWeight: FontWeight.bold,
          fontSize: big ? 18 : 14,
        ),
      ),
    );
  }

  InputDecoration _inputDecor(String hint) {
    return InputDecoration(
      hintText: hint,
      border: const OutlineInputBorder(),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    );
  }

  Widget _buildStyleRow({
    required double fontSize,
    required bool bold,
    required ValueChanged<double> onFontSizeChanged,
    required ValueChanged<bool> onBoldChanged,
    bool? underline,
    ValueChanged<bool>? onUnderlineChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        children: [
          const Text('PDF font size:',
              style: TextStyle(fontSize: 12, color: Colors.grey)),
          const SizedBox(width: 8),
          InkWell(
            onTap: () {
              final next = (fontSize - 1).clamp(6, 40).toDouble();
              onFontSizeChanged(next);
            },
            child: Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: Colors.grey.shade200,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: Colors.grey.shade400),
              ),
              child: const Icon(Icons.remove, size: 16),
            ),
          ),
          Container(
            width: 40,
            alignment: Alignment.center,
            child: Text('${fontSize.toInt()}pt',
                style:
                    const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
          ),
          InkWell(
            onTap: () {
              final next = (fontSize + 1).clamp(6, 40).toDouble();
              onFontSizeChanged(next);
            },
            child: Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: Colors.grey.shade200,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: Colors.grey.shade400),
              ),
              child: const Icon(Icons.add, size: 16),
            ),
          ),
          const SizedBox(width: 16),
          InkWell(
            onTap: () => onBoldChanged(!bold),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: bold ? const Color(0xFFCC0000) : Colors.grey.shade200,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                'B',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  color: bold ? Colors.white : Colors.black54,
                ),
              ),
            ),
          ),
          if (underline != null && onUnderlineChanged != null) ...[
            const SizedBox(width: 8),
            InkWell(
              onTap: () => onUnderlineChanged(!underline),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: underline
                      ? const Color(0xFFCC0000)
                      : Colors.grey.shade200,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  'U',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    decoration: TextDecoration.underline,
                    color: underline ? Colors.white : Colors.black54,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// HTML for the embedded rich text editor iframe.
  /// Uses postMessage to communicate content back to Flutter.
  static const String _editorHtml = '''
<!DOCTYPE html>
<html dir="rtl" lang="ar">
<head>
<meta charset="UTF-8">
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;600;700&display=swap" rel="stylesheet">
<style>
  * { box-sizing: border-box; margin: 0; padding: 0; }
  html, body { background: #fff; font-family: 'Calibri', 'Segoe UI', Tahoma, Arial, sans-serif; font-size: 13px; }
  .toolbar {
    display: flex; flex-wrap: wrap; gap: 2px;
    padding: 4px 6px; background: #f0f0f0;
    border-bottom: 1px solid #ccc;
    position: sticky; top: 0; z-index: 10;
  }
  .toolbar button {
    border: 1px solid #ccc; background: #fff; cursor: pointer;
    padding: 4px 8px; font-size: 13px; border-radius: 3px;
    min-width: 28px; display: flex; align-items: center; justify-content: center;
  }
  .toolbar button:hover { background: #e0e0e0; }
  .toolbar .sep { width: 1px; background: #ccc; margin: 0 4px; }
  .toolbar .tb-select {
    border: 1px solid #ccc; background: #fff; cursor: pointer;
    padding: 4px 6px; font-size: 13px; border-radius: 3px;
    height: 28px;
  }
  .toolbar .tb-select:hover { background: #e0e0e0; }
  .toolbar .color-btn {
    border: 1px solid #ccc; background: #fff; cursor: pointer;
    padding: 4px 8px; font-size: 13px; border-radius: 3px;
    min-width: 28px; height: 28px;
    display: inline-flex; align-items: center; justify-content: center;
    position: relative;
  }
  .toolbar .color-btn:hover { background: #e0e0e0; }
  .toolbar .color-btn #colorSwatch { color: #CC0000; margin-left: 2px; }
  .toolbar .color-btn input[type="color"] {
    position: absolute; inset: 0; opacity: 0; cursor: pointer; border: none;
  }
  #editor {
    min-height: 250px; padding: 12px; outline: none;
    direction: rtl; text-align: right;
    font-family: 'Calibri', 'Segoe UI', Tahoma, Arial, sans-serif;
    font-size: 14px; line-height: 1.8;
    background: #fff;
  }
  #editor img { cursor: pointer; }
  #editor img.img-selected { outline: 2px solid #2196F3; }
  .img-resize-wrap {
    position: relative; display: inline-block; line-height: 0;
  }
  .img-resize-wrap img { display: block; }
  .img-resize-handle {
    position: absolute; width: 10px; height: 10px;
    background: #2196F3; border: 1px solid #fff; border-radius: 2px;
    cursor: nwse-resize; z-index: 20;
  }
  .img-resize-handle.br { bottom: -5px; right: -5px; }
  .img-resize-handle.bl { bottom: -5px; left: -5px; cursor: nesw-resize; }
  .img-resize-handle.tr { top: -5px; right: -5px; cursor: nesw-resize; }
  .img-resize-handle.tl { top: -5px; left: -5px; cursor: nwse-resize; }
  .img-resize-info {
    position: absolute; bottom: -22px; left: 50%; transform: translateX(-50%);
    background: rgba(0,0,0,0.7); color: #fff; font-size: 10px;
    padding: 2px 6px; border-radius: 3px; white-space: nowrap; z-index: 20;
  }
  #editor table { border-collapse: collapse; width: 100%; margin: 8px 0; }
  #editor table td, #editor table th {
    border: 1px solid #999; padding: 4px 8px; min-width: 40px;
  }
  /* Table dialog overlay */
  .tbl-overlay { display:none; position:fixed; top:0; left:0; width:100%; height:100%; background:rgba(0,0,0,0.4); z-index:100; justify-content:center; align-items:center; }
  .tbl-overlay.show { display:flex; }
  .tbl-dialog { background:#fff; border-radius:8px; padding:20px; width:340px; font-size:13px; direction:ltr; }
  .tbl-dialog h3 { margin:0 0 12px; font-size:15px; }
  .tbl-dialog fieldset { border:1px solid #ddd; border-radius:6px; padding:10px; margin-bottom:12px; }
  .tbl-dialog legend { font-weight:bold; font-size:12px; padding:0 6px; }
  .tbl-dialog .row { display:flex; align-items:center; margin-bottom:8px; gap:8px; }
  .tbl-dialog .row label { width:110px; text-align:right; font-size:12px; }
  .tbl-dialog .row input, .tbl-dialog .row select { flex:1; padding:4px 6px; border:1px solid #ccc; border-radius:4px; font-size:12px; }
  .tbl-dialog .row input[type=color] { width:40px; height:28px; padding:0; border:1px solid #ccc; cursor:pointer; }
  .tbl-dialog .row input[type=number] { width:60px; }
  .tbl-dialog .row input[type=checkbox] { width:auto; flex:none; }
  .tbl-dialog .btns { display:flex; gap:8px; justify-content:flex-end; margin-top:12px; }
  .tbl-dialog .btns button { padding:6px 16px; border:1px solid #ccc; border-radius:4px; cursor:pointer; font-size:13px; }
  .tbl-dialog .btns button.ok { background:#CC0000; color:#fff; border-color:#CC0000; }
</style>
</head>
<body>
<div class="toolbar">
  <button onclick="fmt('bold')" title="Bold"><b>B</b></button>
  <button onclick="fmt('underline')" title="Underline"><u>U</u></button>
  <div class="sep"></div>
  <button onclick="fmt('justifyRight')" title="Align Right">&#8614;</button>
  <button onclick="fmt('justifyCenter')" title="Align Center">&#8596;</button>
  <button onclick="fmt('justifyLeft')" title="Align Left">&#8612;</button>
  <button onclick="fmt('justifyFull')" title="Justify">&#9776;</button>
  <div class="sep"></div>
  <button onclick="fmt('insertUnorderedList')" title="Bullets">&#8226;</button>
  <button onclick="fmt('insertOrderedList')" title="Numbered">1.</button>
  <button onclick="fmt('indent')" title="Increase indent">&#8679;</button>
  <button onclick="fmt('outdent')" title="Decrease indent">&#8678;</button>
  <select onchange="applyLineSpacing(this.value); this.value=''" title="Line spacing" class="tb-select">
    <option value="" selected>Spacing</option>
    <option value="1">Single</option>
    <option value="1.15">1.15</option>
    <option value="1.5">1.5</option>
    <option value="2">Double</option>
  </select>
  <div class="sep"></div>
  <button onclick="insertTable()" title="Table">&#9638;</button>
  <div class="sep"></div>
  <button onclick="fmt('undo')" title="Undo">&#8630;</button>
  <button onclick="fmt('redo')" title="Redo">&#8631;</button>
  <div class="sep"></div>
  <select onchange="applyParaStyle(this.value); this.value=''" title="Paragraph style" class="tb-select">
    <option value="" selected>Style</option>
    <option value="p">Normal text</option>
    <option value="h1">Heading 1</option>
    <option value="h2">Heading 2</option>
    <option value="h3">Heading 3</option>
  </select>
  <select onchange="applyFontFamily(this.value); this.value=''" title="Font" class="tb-select">
    <option value="" selected>Font</option>
    <option value="Calibri, 'Segoe UI', sans-serif">Calibri</option>
    <option value="Arial, sans-serif">Arial</option>
    <option value="'Times New Roman', serif">Times New Roman</option>
    <option value="Tahoma, sans-serif">Tahoma</option>
    <option value="Georgia, serif">Georgia</option>
    <option value="'Courier New', monospace">Courier New</option>
    <option value="Verdana, sans-serif">Verdana</option>
    <option value="'Traditional Arabic', 'Arabic Typesetting', serif">Traditional Arabic</option>
    <option value="Inter, system-ui, sans-serif">Inter</option>
  </select>
  <select onchange="applyFontSize(this.value); this.value=''" title="Font Size" class="tb-select">
    <option value="" selected>Size</option>
    <option value="10">10 pt</option>
    <option value="11">11 pt</option>
    <option value="12">12 pt</option>
    <option value="14">14 pt</option>
    <option value="16">16 pt</option>
    <option value="18">18 pt</option>
    <option value="20">20 pt</option>
    <option value="24">24 pt</option>
    <option value="28">28 pt</option>
    <option value="32">32 pt</option>
    <option value="36">36 pt</option>
    <option value="48">48 pt</option>
  </select>
  <label class="color-btn" title="Font Color">A<span id="colorSwatch">&#9607;</span><input type="color" id="fontColorInput" value="#CC0000" onchange="applyFontColor(this.value)" /></label>
  <label class="color-btn" title="Highlight"><span id="hlSwatch" style="color:#FFFF00">&#9607;</span><input type="color" value="#FFFF00" onchange="applyHighlight(this.value); document.getElementById('hlSwatch').style.color=this.value" /></label>
  <button onclick="clearFormatting()" title="Clear formatting">&#9108;</button>
  <div class="sep"></div>
  <button onclick="requestInsertImage()" title="Insert Image">&#128247;</button>
  <div class="sep"></div>
  <select id="zoomSelect" onchange="applyZoom(this.value)" title="Zoom" class="tb-select">
    <option value="0.5">50%</option>
    <option value="0.75">75%</option>
    <option value="1" selected>100%</option>
    <option value="1.25">125%</option>
    <option value="1.5">150%</option>
  </select>
</div>
<div id="editor" contenteditable="true"></div>

<!-- Table Insert Dialog -->
<div class="tbl-overlay" id="tblOverlay">
  <div class="tbl-dialog">
    <h3>Insert Table</h3>
    <fieldset><legend>Table Size</legend>
      <div class="row"><label>Columns:</label><input type="number" id="tblCols" value="2" min="1" max="20"></div>
      <div class="row"><label>Rows:</label><input type="number" id="tblRows" value="2" min="1" max="50"></div>
      <div class="row"><label>Width:</label><select id="tblWidth"><option value="100%">Full width</option><option value="75%">75%</option><option value="50%">50%</option><option value="auto">Auto</option></select></div>
      <div class="row"><label>Equal column widths:</label><input type="checkbox" id="tblEqual" checked></div>
      <div class="row"><label>Height:</label><select id="tblHeight"><option value="auto">AutoFit to contents</option><option value="30px">30px</option><option value="50px">50px</option></select></div>
    </fieldset>
    <fieldset><legend>Layout</legend>
      <div class="row"><label>Cell padding:</label><input type="number" id="tblPadding" value="4" min="0" max="20"></div>
      <div class="row"><label>Cell spacing:</label><input type="number" id="tblSpacing" value="0" min="0" max="10"></div>
    </fieldset>
    <fieldset><legend>Appearance</legend>
      <div class="row"><label>Border size:</label><input type="number" id="tblBorder" value="1" min="0" max="5"></div>
      <div class="row"><label>Border color:</label><input type="color" id="tblBorderColor" value="#000000"></div>
      <div class="row"><label>Background color:</label><input type="color" id="tblBgColor" value="#ffffff"></div>
    </fieldset>
    <div class="btns">
      <button onclick="closeTblDialog()">Cancel</button>
      <button class="ok" onclick="doInsertTable()">OK</button>
    </div>
  </div>
</div>

<script>
function fmt(cmd, val) { document.execCommand(cmd, false, val || null); }

function insertTable() {
  document.getElementById("tblOverlay").classList.add("show");
}
function closeTblDialog() {
  document.getElementById("tblOverlay").classList.remove("show");
}
function doInsertTable() {
  var cols = parseInt(document.getElementById("tblCols").value) || 2;
  var rows = parseInt(document.getElementById("tblRows").value) || 2;
  var width = document.getElementById("tblWidth").value;
  var height = document.getElementById("tblHeight").value;
  var padding = document.getElementById("tblPadding").value;
  var spacing = document.getElementById("tblSpacing").value;
  var border = document.getElementById("tblBorder").value;
  var borderColor = document.getElementById("tblBorderColor").value;
  var bgColor = document.getElementById("tblBgColor").value;
  var equalW = document.getElementById("tblEqual").checked;

  var colW = equalW ? (100 / cols).toFixed(1) + "%" : "auto";
  var tdStyle = "border:" + border + "px solid " + borderColor + ";padding:" + padding + "px;";
  if (height !== "auto") tdStyle += "height:" + height + ";";
  if (bgColor !== "#ffffff") tdStyle += "background:" + bgColor + ";";

  var t = '<table style="width:' + width + ';border-collapse:collapse;border-spacing:' + spacing + 'px;border:' + border + 'px solid ' + borderColor + ';">';
  for (var r = 0; r < rows; r++) {
    t += "<tr>";
    for (var c = 0; c < cols; c++) {
      t += '<td style="' + tdStyle + (equalW ? "width:" + colW + ";" : "") + '">&nbsp;</td>';
    }
    t += "</tr>";
  }
  t += "</table><br>";
  closeTblDialog();
  document.getElementById("editor").focus();
  document.execCommand("insertHTML", false, t);
}
function wrapSelectionWithStyle(styleProp, styleVal) {
  var editor = document.getElementById("editor");
  editor.focus();
  var sel = window.getSelection();
  if (!sel.rangeCount) return;
  var range = sel.getRangeAt(0);

  if (!sel.isCollapsed) {
    var walker = document.createTreeWalker(
      editor,
      NodeFilter.SHOW_TEXT,
      {
        acceptNode: function(node) {
          if (!node.nodeValue || !node.nodeValue.trim()) return NodeFilter.FILTER_REJECT;
          if (!range.intersectsNode(node)) return NodeFilter.FILTER_REJECT;
          return NodeFilter.FILTER_ACCEPT;
        }
      }
    );
    var textNodes = [];
    var n;
    while ((n = walker.nextNode())) textNodes.push(n);

    textNodes.forEach(function(tn) {
      var startOffset = 0;
      var endOffset = tn.nodeValue.length;
      if (tn === range.startContainer) startOffset = range.startOffset;
      if (tn === range.endContainer) endOffset = range.endOffset;
      if (startOffset >= endOffset) return;

      var middle = tn;
      if (endOffset < tn.nodeValue.length) {
        middle.splitText(endOffset);
      }
      if (startOffset > 0) {
        middle = middle.splitText(startOffset);
      }

      if (middle.parentNode && middle.parentNode.nodeName === "SPAN" &&
          middle.parentNode.childNodes.length === 1 &&
          middle.parentNode.style && middle.parentNode.style[styleProp]) {
        middle.parentNode.style[styleProp] = styleVal;
        return;
      }

      var span = document.createElement("span");
      span.style[styleProp] = styleVal;
      middle.parentNode.insertBefore(span, middle);
      span.appendChild(middle);
    });
    return;
  }

  var span = document.createElement("span");
  span.style[styleProp] = styleVal;
  var zwsp = document.createTextNode("\u200B");
  span.appendChild(zwsp);
  range.insertNode(span);

  var newRange = document.createRange();
  newRange.setStart(zwsp, 1);
  newRange.setEnd(zwsp, 1);
  sel.removeAllRanges();
  sel.addRange(newRange);
}
function applyFontSize(s) {
  if (!s) return;
  document.getElementById("editor").focus();
  wrapSelectionWithStyle("fontSize", s + "pt");
}
function applyFontColor(c) {
  if (!c) return;
  var swatch = document.getElementById("colorSwatch");
  if (swatch) swatch.style.color = c;
  document.getElementById("editor").focus();
  wrapSelectionWithStyle("color", c);
}
function applyHighlight(c) {
  if (!c) return;
  document.getElementById("editor").focus();
  wrapSelectionWithStyle("backgroundColor", c);
}
function applyLineSpacing(v) {
  if (!v) return;
  var editor = document.getElementById("editor");
  editor.focus();
  var sel = window.getSelection();
  if (!sel.rangeCount) return;
  var range = sel.getRangeAt(0);
  var blockTags = ["P", "DIV", "H1", "H2", "H3", "H4", "H5", "H6", "LI", "BLOCKQUOTE"];
  var blocks = [];
  var walker = document.createTreeWalker(editor, NodeFilter.SHOW_ELEMENT, {
    acceptNode: function(node) {
      if (blockTags.indexOf(node.nodeName) === -1) return NodeFilter.FILTER_SKIP;
      if (!range.intersectsNode(node)) return NodeFilter.FILTER_REJECT;
      return NodeFilter.FILTER_ACCEPT;
    }
  });
  var n;
  while ((n = walker.nextNode())) blocks.push(n);
  if (blocks.length === 0) {
    var el = range.commonAncestorContainer;
    if (el.nodeType === Node.TEXT_NODE) el = el.parentNode;
    while (el && el !== editor && blockTags.indexOf(el.nodeName) === -1) el = el.parentNode;
    if (el && el !== editor) blocks.push(el);
  }
  blocks.forEach(function(b) { b.style.lineHeight = v; });
}
function clearFormatting() {
  document.getElementById("editor").focus();
  document.execCommand("removeFormat");
  var sel = window.getSelection();
  if (sel.rangeCount && !sel.isCollapsed) {
    document.execCommand("formatBlock", false, "p");
  }
}
function applyZoom(z) {
  document.getElementById("editor").style.zoom = z;
}
function applyParaStyle(tag) {
  if (!tag) return;
  document.getElementById("editor").focus();
  document.execCommand("formatBlock", false, tag);
}
function applyFontFamily(f) {
  if (!f) return;
  document.getElementById("editor").focus();
  wrapSelectionWithStyle("fontFamily", f);
}
// ── Table context menu (right-click on cells) ──
var ctxMenu = null;
var ctxCell = null;

document.getElementById("editor").addEventListener("contextmenu", function(e) {
  var td = e.target.closest("td, th");
  if (!td) return;
  e.preventDefault();
  ctxCell = td;
  if (ctxMenu) ctxMenu.remove();

  ctxMenu = document.createElement("div");
  ctxMenu.style.cssText = "position:fixed;z-index:200;background:#fff;border:1px solid #ccc;border-radius:6px;box-shadow:0 2px 8px rgba(0,0,0,0.15);padding:4px 0;font-size:13px;min-width:180px;";
  var items = [
    {label:"Merge Right", action:"mergeRight"},
    {label:"Merge Down", action:"mergeDown"},
    {label:"Split Cell", action:"split"},
    {label:"---"},
    {label:"Insert Row Above", action:"rowAbove"},
    {label:"Insert Row Below", action:"rowBelow"},
    {label:"Insert Column Left", action:"colLeft"},
    {label:"Insert Column Right", action:"colRight"},
    {label:"---"},
    {label:"Delete Row", action:"delRow"},
    {label:"Delete Column", action:"delCol"},
  ];
  items.forEach(function(item) {
    if (item.label === "---") {
      var hr = document.createElement("div");
      hr.style.cssText = "border-top:1px solid #eee;margin:4px 0;";
      ctxMenu.appendChild(hr);
    } else {
      var btn = document.createElement("div");
      btn.textContent = item.label;
      btn.style.cssText = "padding:6px 16px;cursor:pointer;";
      btn.onmouseover = function() { this.style.background="#f0f0f0"; };
      btn.onmouseout = function() { this.style.background=""; };
      btn.onclick = function() { tableAction(item.action); ctxMenu.remove(); ctxMenu=null; };
      ctxMenu.appendChild(btn);
    }
  });
  ctxMenu.style.left = e.clientX + "px";
  ctxMenu.style.top = e.clientY + "px";
  document.body.appendChild(ctxMenu);
});

document.addEventListener("click", function() {
  if (ctxMenu) { ctxMenu.remove(); ctxMenu = null; }
});

function tableAction(action) {
  if (!ctxCell) return;
  var tr = ctxCell.parentElement;
  var table = tr.parentElement;
  if (table.tagName === "TBODY") table = table.parentElement;
  var cellIndex = ctxCell.cellIndex;
  var rowIndex = tr.rowIndex;

  if (action === "mergeRight") {
    var next = ctxCell.nextElementSibling;
    if (!next) return;
    var cs = parseInt(ctxCell.getAttribute("colspan") || 1);
    var ns = parseInt(next.getAttribute("colspan") || 1);
    ctxCell.innerHTML += " " + next.innerHTML;
    ctxCell.setAttribute("colspan", cs + ns);
    next.remove();
  }
  else if (action === "mergeDown") {
    var nextRow = table.rows[rowIndex + 1];
    if (!nextRow) return;
    var below = nextRow.cells[cellIndex];
    if (!below) return;
    var rs = parseInt(ctxCell.getAttribute("rowspan") || 1);
    var bs = parseInt(below.getAttribute("rowspan") || 1);
    ctxCell.innerHTML += "<br>" + below.innerHTML;
    ctxCell.setAttribute("rowspan", rs + bs);
    below.remove();
  }
  else if (action === "split") {
    var cs = parseInt(ctxCell.getAttribute("colspan") || 1);
    var rs = parseInt(ctxCell.getAttribute("rowspan") || 1);
    if (cs > 1) {
      ctxCell.setAttribute("colspan", 1);
      for (var i = 1; i < cs; i++) {
        var nc = document.createElement("td");
        nc.innerHTML = "&nbsp;";
        nc.style.cssText = ctxCell.style.cssText;
        ctxCell.after(nc);
      }
    } else if (rs > 1) {
      ctxCell.setAttribute("rowspan", 1);
      for (var i = 1; i < rs; i++) {
        var nr = table.rows[rowIndex + i];
        if (nr) {
          var nc = document.createElement("td");
          nc.innerHTML = "&nbsp;";
          nc.style.cssText = ctxCell.style.cssText;
          if (nr.cells[cellIndex]) nr.cells[cellIndex].before(nc);
          else nr.appendChild(nc);
        }
      }
    }
  }
  else if (action === "rowAbove") {
    var newRow = tr.cloneNode(true);
    Array.from(newRow.cells).forEach(function(c) { c.innerHTML = "&nbsp;"; });
    tr.before(newRow);
  }
  else if (action === "rowBelow") {
    var newRow = tr.cloneNode(true);
    Array.from(newRow.cells).forEach(function(c) { c.innerHTML = "&nbsp;"; });
    tr.after(newRow);
  }
  else if (action === "colLeft") {
    Array.from(table.rows).forEach(function(r) {
      var nc = document.createElement("td");
      nc.innerHTML = "&nbsp;";
      if (r.cells[cellIndex]) { nc.style.cssText = r.cells[cellIndex].style.cssText; r.cells[cellIndex].before(nc); }
      else r.appendChild(nc);
    });
  }
  else if (action === "colRight") {
    Array.from(table.rows).forEach(function(r) {
      var nc = document.createElement("td");
      nc.innerHTML = "&nbsp;";
      var ref = r.cells[cellIndex];
      if (ref) { nc.style.cssText = ref.style.cssText; ref.after(nc); }
      else r.appendChild(nc);
    });
  }
  else if (action === "delRow") {
    if (table.rows.length > 1) tr.remove();
  }
  else if (action === "delCol") {
    Array.from(table.rows).forEach(function(r) {
      if (r.cells[cellIndex]) r.cells[cellIndex].remove();
    });
  }
}

// --- Image resize logic ---
var _activeImg = null;
function _clearResize() {
  var old = document.querySelector(".img-resize-wrap");
  if (old) {
    var img = old.querySelector("img");
    if (img) { old.parentNode.insertBefore(img, old); old.remove(); }
  }
  _activeImg = null;
}
function _wrapForResize(img) {
  _clearResize();
  _activeImg = img;
  var wrap = document.createElement("span");
  wrap.className = "img-resize-wrap";
  wrap.contentEditable = "false";
  img.parentNode.insertBefore(wrap, img);
  wrap.appendChild(img);
  var corners = ["br","bl","tr","tl"];
  corners.forEach(function(c) {
    var h = document.createElement("span");
    h.className = "img-resize-handle " + c;
    h.addEventListener("mousedown", function(ev) { _startResize(ev, img, c); });
    wrap.appendChild(h);
  });
  var info = document.createElement("span");
  info.className = "img-resize-info";
  info.textContent = Math.round(img.offsetWidth) + " x " + Math.round(img.offsetHeight);
  wrap.appendChild(info);
}
function _startResize(ev, img, corner) {
  ev.preventDefault(); ev.stopPropagation();
  var startX = ev.clientX, startY = ev.clientY;
  var startW = img.offsetWidth, startH = img.offsetHeight;
  var ratio = startW / startH;
  var info = img.parentNode.querySelector(".img-resize-info");
  function onMove(e) {
    var dx = e.clientX - startX, dy = e.clientY - startY;
    var nw = startW, nh = startH;
    if (corner === "br") { nw = startW + dx; }
    else if (corner === "bl") { nw = startW - dx; }
    else if (corner === "tr") { nw = startW + dx; }
    else if (corner === "tl") { nw = startW - dx; }
    if (nw < 30) nw = 30;
    nh = nw / ratio;
    img.style.width = Math.round(nw) + "px";
    img.style.height = Math.round(nh) + "px";
    img.style.maxWidth = "none";
    if (info) info.textContent = Math.round(nw) + " x " + Math.round(nh);
  }
  function onUp() {
    document.removeEventListener("mousemove", onMove);
    document.removeEventListener("mouseup", onUp);
  }
  document.addEventListener("mousemove", onMove);
  document.addEventListener("mouseup", onUp);
}
document.getElementById("editor").addEventListener("click", function(ev) {
  if (ev.target.tagName === "IMG" && !ev.target.closest(".img-resize-wrap")) {
    _wrapForResize(ev.target);
  } else if (!ev.target.closest(".img-resize-wrap")) {
    _clearResize();
  }
});
document.addEventListener("keydown", function(ev) {
  if (_activeImg && (ev.key === "Escape" || ev.key === "Delete" || ev.key === "Backspace")) {
    if (ev.key === "Escape") { _clearResize(); }
    else { var w = _activeImg.closest(".img-resize-wrap"); if (w) w.remove(); else _activeImg.remove(); _activeImg = null; }
  }
});

// Listen for parent requests
function requestInsertImage(){parent.postMessage("INSERT_IMAGE_REQUEST","*");}
window.addEventListener("message", function(e) {
  if (e.data === "GET_HTML") {
    _clearResize();
    var html = document.getElementById("editor").innerHTML || "";
    parent.postMessage("EDITOR_HTML:" + html, "*");
  } else if (typeof e.data === "string" && e.data.startsWith("SET_HTML:")) {
    document.getElementById("editor").innerHTML = e.data.substring(9);
  } else if (typeof e.data === "string" && e.data.startsWith("INSERT_IMAGE:")) {
    var url = e.data.substring(13);
    var ld = document.getElementById("img-loading");
    if (ld) ld.remove();
    document.getElementById("editor").focus();
    document.execCommand("insertHTML", false, '<img src="' + url + '" style="max-width:100%;">');
  } else if (typeof e.data === "string" && e.data.startsWith("INSERT_IMAGE_ERROR:")) {
    alert(e.data.substring(19));
  } else if (e.data === "INSERT_IMAGE_LOADING") {
    document.getElementById("editor").focus();
    document.execCommand("insertHTML", false, '<span id="img-loading" style="display:inline-block;padding:8px 16px;background:#f0f0f0;border:1px dashed #999;border-radius:4px;color:#666;font-style:italic;">Uploading image...</span>');
  } else if (e.data === "REMOVE_IMAGE_LOADING") {
    var el = document.getElementById("img-loading");
    if (el) el.remove();
  }
});
// Notify parent that editor is ready
window.addEventListener("load", function() {
  parent.postMessage("EDITOR_READY", "*");
});
</script>
</body>
</html>
''';
}

class _Attachment {
  final String name;
  final Uint8List bytes;
  final String base64;
  final bool isImage;

  const _Attachment({
    required this.name,
    required this.bytes,
    required this.base64,
    required this.isImage,
  });
}
