import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:printing/printing.dart';
import '../../models/generated_letter.dart';
import '../../services/letter_service.dart';
import '../../theme/app_theme.dart';

class LetterFormTab extends StatefulWidget {
  final VoidCallback onLetterSaved;

  const LetterFormTab({super.key, required this.onLetterSaved});

  @override
  State<LetterFormTab> createState() => _LetterFormTabState();
}

class _LetterFormTabState extends State<LetterFormTab> {
  final _formKey = GlobalKey<FormState>();
  final _isharaCtrl = TextEditingController();
  final _alsayedCtrl = TextEditingController();
  final _almawdooCtrl = TextEditingController();
  final _bodyCtrl = TextEditingController();
  final _alasmCtrl = TextEditingController();
  DateTime? _selectedDate;
  Uint8List? _signatureBytes;
  String? _signatureBase64;
  bool _isLoading = false;
  bool _hasPreviewedOnce = false;

  String _formatDate(DateTime d) {
    return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
  }

  Future<void> _pickDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (date != null) {
      setState(() => _selectedDate = date);
    }
  }

  Future<void> _pickSignature() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowedExtensions: ['png', 'jpg', 'jpeg'],
    );
    if (result != null && result.files.isNotEmpty) {
      final file = result.files.first;
      if (file.size > 5 * 1024 * 1024) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('حجم الملف يجب أن يكون أقل من 5MB')),
          );
        }
        return;
      }
      final bytes = file.bytes;
      if (bytes != null) {
        final base64Data = base64Encode(bytes);
        setState(() {
          _signatureBytes = bytes;
          _signatureBase64 = 'data:image/png;base64,$base64Data';
        });
      }
    }
  }

  void _showPreview() {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        insetPadding: const EdgeInsets.all(16),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 600, maxHeight: 800),
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('معاينة الخطاب',
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const Divider(),
              Expanded(
                child: SingleChildScrollView(
                  child: AspectRatio(
                    aspectRatio: 1 / 1.414,
                    child: Container(
                      color: Colors.white,
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Image.asset(
                                  'assets/images/logo_civilaviation.png',
                                  height: 40),
                              Image.asset('assets/images/logo_emblem.png',
                                  height: 40),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Container(height: 3, color: const Color(0xFFCC0000)),
                          const SizedBox(height: 16),
                          Text('الإشارة: ${_isharaCtrl.text}',
                              textAlign: TextAlign.right,
                              style: const TextStyle(fontSize: 12)),
                          Text(
                              'التاريخ: ${_selectedDate != null ? _formatDate(_selectedDate!) : ''}',
                              textAlign: TextAlign.right,
                              style: const TextStyle(fontSize: 12)),
                          const SizedBox(height: 8),
                          Text('السيد / ${_alsayedCtrl.text}',
                              textAlign: TextAlign.right,
                              style: const TextStyle(
                                  fontSize: 12, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 16),
                          Center(
                            child: Text(_almawdooCtrl.text,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                    fontSize: 14, fontWeight: FontWeight.bold)),
                          ),
                          const SizedBox(height: 16),
                          Text('\t${_bodyCtrl.text}',
                              textAlign: TextAlign.right,
                              style: const TextStyle(fontSize: 12)),
                          const SizedBox(height: 16),
                          Text(_alasmCtrl.text,
                              textAlign: TextAlign.right,
                              style: const TextStyle(fontSize: 12)),
                          if (_signatureBytes != null) ...[
                            const SizedBox(height: 8),
                            Image.memory(_signatureBytes!, height: 60),
                          ],
                          const SizedBox(height: 16),
                          const Text('المرفقات:',
                              textAlign: TextAlign.right,
                              style: TextStyle(fontSize: 12)),
                          const Spacer(),
                          const Center(
                            child: Text(
                              'E-mail: info@dgca.gov.kw | www.dgca.gov.kw | P.O.Box: 17 Safat, 13001 Kuwait | Tel: (+965) 2434-7171 | Fax: (+965) 2431-5504',
                              textAlign: TextAlign.center,
                              style: TextStyle(fontSize: 8),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _generatePdf,
                child: const Text('توليد PDF'),
              ),
            ],
          ),
        ),
      ),
    );
    setState(() => _hasPreviewedOnce = true);
  }

  Future<void> _generatePdf() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('الرجاء اختيار التاريخ')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final letter = GeneratedLetter(
        ishara: _isharaCtrl.text,
        tarikh: _selectedDate!.toIso8601String().split('T')[0],
        alsayed: _alsayedCtrl.text,
        almawdoo: _almawdooCtrl.text,
        bodyText: _bodyCtrl.text,
        alasm: _alasmCtrl.text,
        signatureBase64: _signatureBase64,
      );

      final pdfBytes = await LetterService().generate(letter);
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      await Printing.sharePdf(
          bytes: pdfBytes, filename: 'letter_$timestamp.pdf');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم توليد الخطاب بنجاح')),
        );
        widget.onLetterSaved();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ: $e')),
        );
      }
    }

    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  void _removeSignature() {
    setState(() {
      _signatureBytes = null;
      _signatureBase64 = null;
    });
  }

  @override
  void dispose() {
    _isharaCtrl.dispose();
    _alsayedCtrl.dispose();
    _almawdooCtrl.dispose();
    _bodyCtrl.dispose();
    _alasmCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextFormField(
              controller: _isharaCtrl,
              decoration: const InputDecoration(
                labelText: 'الإشارة',
                border: OutlineInputBorder(),
              ),
              validator: (v) => v == null || v.isEmpty ? 'مطلوب' : null,
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    readOnly: true,
                    controller: TextEditingController(
                      text: _selectedDate != null
                          ? _formatDate(_selectedDate!)
                          : '',
                    ),
                    decoration: const InputDecoration(
                      labelText: 'التاريخ',
                      border: OutlineInputBorder(),
                    ),
                    onTap: _pickDate,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.calendar_today),
                  onPressed: _pickDate,
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _alsayedCtrl,
              decoration: const InputDecoration(
                labelText: 'السيد',
                border: OutlineInputBorder(),
              ),
              validator: (v) => v == null || v.isEmpty ? 'مطلوب' : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _almawdooCtrl,
              decoration: const InputDecoration(
                labelText: 'الموضوع',
                border: OutlineInputBorder(),
              ),
              maxLines: 3,
              minLines: 2,
              validator: (v) => v == null || v.isEmpty ? 'مطلوب' : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _bodyCtrl,
              decoration: const InputDecoration(
                labelText: 'بالإشارة للموضوع أعلاه',
                border: OutlineInputBorder(),
              ),
              maxLines: 8,
              minLines: 4,
              validator: (v) => v == null || v.isEmpty ? 'مطلوب' : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _alasmCtrl,
              decoration: const InputDecoration(
                labelText: 'الاسم',
                border: OutlineInputBorder(),
              ),
              validator: (v) => v == null || v.isEmpty ? 'مطلوب' : null,
            ),
            const SizedBox(height: 16),
            if (_signatureBytes == null)
              OutlinedButton.icon(
                onPressed: _pickSignature,
                icon: const Icon(Icons.upload),
                label: const Text('رفع التوقيع'),
              )
            else
              Row(
                children: [
                  Image.memory(_signatureBytes!, height: 80),
                  IconButton(
                    icon: const Icon(Icons.delete, color: AppColors.dangerText),
                    onPressed: _removeSignature,
                  ),
                ],
              ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _formKey.currentState?.validate() == true
                        ? _showPreview
                        : null,
                    child: const Text('معاينة'),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _hasPreviewedOnce && !_isLoading
                        ? () {
                            if (_formKey.currentState!.validate()) {
                              _generatePdf();
                            }
                          }
                        : null,
                    child: _isLoading
                        ? const CircularProgressIndicator()
                        : const Text('توليد PDF'),
                  ),
                ),
              ],
            ),
            if (!_hasPreviewedOnce)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'يجب معاينة الخطاب أولاً',
                  style: TextStyle(color: AppColors.textTertiary, fontSize: 12),
                  textAlign: TextAlign.center,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
