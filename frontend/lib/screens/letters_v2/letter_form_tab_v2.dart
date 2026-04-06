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
import '../../config.dart';
import '../../models/generated_letter.dart';
import '../../services/letter_service.dart';

/// Letter form with WYSIWYG rich text editor (v2 — WeasyPrint backend).
class LetterFormTabV2 extends StatefulWidget {
  final VoidCallback onLetterSaved;
  final GeneratedLetter? editLetter;

  const LetterFormTabV2({super.key, required this.onLetterSaved, this.editLetter});

  @override
  State<LetterFormTabV2> createState() => _LetterFormTabV2State();
}

class _LetterFormTabV2State extends State<LetterFormTabV2> {
  final _formKey = GlobalKey<FormState>();
  final _isharaCtrl = TextEditingController();
  final _alsayedCtrl = TextEditingController();
  final _almawdooCtrl = TextEditingController();
  final _alasmCtrl = TextEditingController();
  final _ccListCtrl = TextEditingController();

  Uint8List? _signatureBytes;
  String? _signatureBase64;
  bool _replyRequired = false;
  bool _isLoading = false;
  bool _hasPreviewedOnce = false;
  String? _editingLetterId;
  String? _initialBodyHtml;

  // Attachments
  final List<_Attachment> _attachments = [];

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
      _alasmCtrl.text = letter.alasm;
      _initialBodyHtml = letter.bodyText;
      if (letter.signatureBase64 != null && letter.signatureBase64!.isNotEmpty) {
        _signatureBase64 = letter.signatureBase64;
        try {
          String b64 = letter.signatureBase64!;
          if (b64.contains(',')) b64 = b64.split(',').last;
          _signatureBytes = base64Decode(b64);
        } catch (_) {}
      }
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
            SnackBar(content: Text('${file.name}: حجم الملف يتجاوز 10 ميغابايت')),
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
          const SnackBar(content: Text('حجم الملف يتجاوز 5 ميغابايت')),
        );
      }
      return;
    }
    setState(() {
      _signatureBytes = file.bytes;
      _signatureBase64 = base64Encode(file.bytes!);
    });
  }

  Future<void> _showPreview() async {
    if (!_formKey.currentState!.validate()) return;
    final bodyHtml = await _getEditorHtml();
    if (bodyHtml.trim().isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('يرجى كتابة نص الخطاب')),
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
        'alsayed': _alsayedCtrl.text,
        'almawdoo': _almawdooCtrl.text,
        'body_html': bodyHtml,
        'alasm': _alasmCtrl.text,
        'signature_base64': _signatureBase64,
        'reply_required': _replyRequired,
        'cc_list': _ccListCtrl.text.isEmpty ? null : _ccListCtrl.text,
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
        const SnackBar(content: Text('فشل تحميل المعاينة')),
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
                      'معاينة الخطاب',
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
                      child: const Text('إغلاق'),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      onPressed: () {
                        Navigator.pop(ctx);
                        _generatePdf();
                      },
                      icon: const Icon(Icons.picture_as_pdf),
                      label: const Text('توليد PDF'),
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
        const SnackBar(content: Text('يرجى كتابة نص الخطاب')),
      );
      return;
    }

    setState(() => _isLoading = true);
    try {
      final body = {
        'ishara': _isharaCtrl.text,
        'alsayed': _alsayedCtrl.text,
        'almawdoo': _almawdooCtrl.text,
        'body_html': bodyHtml,
        'alasm': _alasmCtrl.text,
        'signature_base64': _signatureBase64,
        'reply_required': _replyRequired,
        'cc_list': _ccListCtrl.text.isEmpty ? null : _ccListCtrl.text,
        'attachments': _attachments.map((_Attachment a) => <String, dynamic>{
          'name': a.name,
          'data': a.base64,
          'is_image': a.isImage,
        }).toList(),
      };

      final Uint8List pdfBytes;
      if (_editingLetterId != null) {
        pdfBytes = await LetterService().updateV2(_editingLetterId!, body);
      } else {
        pdfBytes = await LetterService().generateV2(body);
      }
      await Printing.sharePdf(
        bytes: pdfBytes,
        filename: 'letter_${DateTime.now().millisecondsSinceEpoch}.pdf',
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_editingLetterId != null
              ? 'تم تحديث الخطاب بنجاح'
              : 'تم توليد الخطاب بنجاح')),
        );
      }
      widget.onLetterSaved();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ: $e')),
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
    _alasmCtrl.dispose();
    _ccListCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Reference Number (رقم الإشارة) ──
            _buildLabel('رقم الإشارة'),
            TextFormField(
              controller: _isharaCtrl,
              decoration: _inputDecor('مثال: 2026-23279'),
              textDirection: TextDirection.ltr,
              validator: (v) =>
                  (v == null || v.isEmpty) ? 'مطلوب' : null,
            ),
            const SizedBox(height: 16),

            // ── Recipient (السيد) ──
            _buildLabel('السيد /'),
            TextFormField(
              controller: _alsayedCtrl,
              decoration: _inputDecor('اسم المستلم والمسمى الوظيفي'),
              validator: (v) =>
                  (v == null || v.isEmpty) ? 'مطلوب' : null,
            ),
            const Padding(
              padding: EdgeInsets.only(top: 4, right: 8),
              child: Text('المحترم',
                  style: TextStyle(fontSize: 13, color: Colors.grey)),
            ),
            const SizedBox(height: 16),

            // ── Subject (الموضوع) ──
            _buildLabel('الموضوع'),
            TextFormField(
              controller: _almawdooCtrl,
              decoration: _inputDecor('موضوع الخطاب'),
              maxLines: 3,
              minLines: 2,
              validator: (v) =>
                  (v == null || v.isEmpty) ? 'مطلوب' : null,
            ),
            const SizedBox(height: 16),

            // ── Rich Text Editor (Body) ──
            _buildLabel('نص الخطاب'),
            Container(
              height: 350,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey.shade400),
                borderRadius: BorderRadius.circular(8),
              ),
              clipBehavior: Clip.hardEdge,
              child: HtmlElementView(viewType: _editorViewType),
            ),
            const SizedBox(height: 16),

            // ── Signer (الاسم) ──
            _buildLabel('الاسم'),
            TextFormField(
              controller: _alasmCtrl,
              decoration: _inputDecor('اسم الموقع والمسمى الوظيفي'),
              validator: (v) =>
                  (v == null || v.isEmpty) ? 'مطلوب' : null,
            ),
            const SizedBox(height: 16),

            // ── Reply Required (مطلوب الرد) ──
            Row(
              children: [
                Checkbox(
                  value: _replyRequired,
                  onChanged: (v) =>
                      setState(() => _replyRequired = v ?? false),
                ),
                const Text('مطلوب الرد',
                    style: TextStyle(fontSize: 14)),
              ],
            ),
            const SizedBox(height: 12),

            // ── CC List (قائمة النسخ) ──
            _buildLabel('قائمة النسخ'),
            TextFormField(
              controller: _ccListCtrl,
              decoration: _inputDecor('أسماء الجهات المنسوخة (اختياري)'),
            ),
            const SizedBox(height: 16),

            // ── Attachments (المرفقات) ──
            _buildLabel('المرفقات'),
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
                            child: Image.memory(att.bytes, width: 40, height: 40, fit: BoxFit.cover),
                          )
                        : const Icon(Icons.attach_file),
                    title: Text(att.name, style: const TextStyle(fontSize: 13)),
                    subtitle: Text('${(att.bytes.lengthInBytes / 1024).toStringAsFixed(0)} KB',
                        style: const TextStyle(fontSize: 11)),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline, color: Colors.red, size: 20),
                      onPressed: () => setState(() => _attachments.removeAt(i)),
                    ),
                    dense: true,
                  ),
                );
              }),
            OutlinedButton.icon(
              onPressed: _pickAttachments,
              icon: const Icon(Icons.attach_file),
              label: const Text('إضافة مرفق'),
            ),
            const SizedBox(height: 16),

            // ── Signature Upload (التوقيع الإلكتروني) ──
            _buildLabel('التوقيع الإلكتروني'),
            if (_signatureBytes != null)
              Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: Image.memory(_signatureBytes!, height: 70),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.delete_outline,
                        color: Colors.red),
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
                label: const Text('رفع التوقيع'),
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
                  child: const Text('الغاء'),
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
                  child: const Text('معاينة'),
                ),
                const SizedBox(width: 12),
                ElevatedButton.icon(
                  onPressed: (_hasPreviewedOnce && !_isLoading)
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
                      : const Icon(Icons.picture_as_pdf),
                  label: const Text('توليد PDF'),
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
            if (!_hasPreviewedOnce)
              const Padding(
                padding: EdgeInsets.only(top: 6),
                child: Text(
                  'يجب معاينة الخطاب أولاً قبل التوليد',
                  style: TextStyle(fontSize: 11, color: Colors.orange),
                ),
              ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        text,
        style:
            const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
      ),
    );
  }

  InputDecoration _inputDecor(String hint) {
    return InputDecoration(
      hintText: hint,
      border: const OutlineInputBorder(),
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    );
  }

  /// HTML for the embedded rich text editor iframe.
  /// Uses postMessage to communicate content back to Flutter.
  static const String _editorHtml = '''
<!DOCTYPE html>
<html dir="rtl" lang="ar">
<head>
<meta charset="UTF-8">
<style>
  * { box-sizing: border-box; margin: 0; padding: 0; }
  html, body { background: #fff; font-family: 'Segoe UI', Tahoma, Arial, sans-serif; font-size: 13px; }
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
  #editor {
    min-height: 250px; padding: 12px; outline: none;
    direction: rtl; text-align: right;
    font-family: 'Segoe UI', Tahoma, Arial, sans-serif;
    font-size: 14px; line-height: 1.8;
    background: #fff;
  }
  #editor table { border-collapse: collapse; width: 100%; margin: 8px 0; }
  #editor table td, #editor table th {
    border: 1px solid #999; padding: 4px 8px; min-width: 40px;
  }
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
  <div class="sep"></div>
  <button onclick="insertTable()" title="Table">&#9638;</button>
  <div class="sep"></div>
  <button onclick="fmt('undo')" title="Undo">&#8630;</button>
  <button onclick="fmt('redo')" title="Redo">&#8631;</button>
  <div class="sep"></div>
  <button onclick="changeFontSize()" title="Font Size">A&#8597;</button>
  <button onclick="changeColor()" title="Font Color">A<span style="color:red">&#9607;</span></button>
</div>
<div id="editor" contenteditable="true"></div>
<script>
function fmt(cmd, val) { document.execCommand(cmd, false, val || null); }
function insertTable() {
  var rows = prompt("\\u0639\\u062f\\u062f \\u0627\\u0644\\u0635\\u0641\\u0648\\u0641:", "3");
  var cols = prompt("\\u0639\\u062f\\u062f \\u0627\\u0644\\u0623\\u0639\\u0645\\u062f\\u0629:", "3");
  if (!rows || !cols) return;
  var t = "<table>";
  for (var r = 0; r < parseInt(rows); r++) {
    t += "<tr>";
    for (var c = 0; c < parseInt(cols); c++) t += "<td>&nbsp;</td>";
    t += "</tr>";
  }
  t += "</table>";
  document.execCommand("insertHTML", false, t);
}
function changeFontSize() {
  var s = prompt("حجم الخط (pt):", "16");
  if (!s) return;
  var sel = window.getSelection();
  if (!sel.rangeCount) return;
  var range = sel.getRangeAt(0);
  var span = document.createElement("span");
  span.style.fontSize = s + "pt";
  range.surroundContents(span);
  sel.removeAllRanges();
}
function changeColor() {
  var c = prompt("Color (hex):", "#CC0000");
  if (c) fmt("foreColor", c);
}
// Listen for parent requests
window.addEventListener("message", function(e) {
  if (e.data === "GET_HTML") {
    var html = document.getElementById("editor").innerHTML || "";
    parent.postMessage("EDITOR_HTML:" + html, "*");
  } else if (typeof e.data === "string" && e.data.startsWith("SET_HTML:")) {
    document.getElementById("editor").innerHTML = e.data.substring(9);
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
