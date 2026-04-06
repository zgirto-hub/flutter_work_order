import 'package:flutter/material.dart';
import '../services/ai_assist_service.dart';

class AiDocumentExpertWidget extends StatefulWidget {
  final Future<String> Function() onGetHtml;
  final void Function(String html) onApplyHtml;

  const AiDocumentExpertWidget({
    super.key,
    required this.onGetHtml,
    required this.onApplyHtml,
  });

  @override
  State<AiDocumentExpertWidget> createState() => _AiDocumentExpertWidgetState();
}

class _AiDocumentExpertWidgetState extends State<AiDocumentExpertWidget> {
  final _instructionsCtrl = TextEditingController();
  final _aiAssistService = AiAssistService();

  bool _isExpanded = false;
  bool? _isAvailable;
  bool _isLoading = false;
  String? _resultHtml;
  int _requestId = 0;

  static const Map<String, String> _actionLabels = {
    'improve': 'تحسين وتنسيق',
    'correct': 'تصحيح نحوي',
    'generate': 'توليد من ملاحظات',
    'translate': 'ترجمة',
    'concise': 'تلخيص',
    'elaborate': 'توسيع',
  };

  String _selectedLanguage = 'ar';

  bool get _hasContent {
    return _resultHtml != null && _resultHtml!.isNotEmpty;
  }

  bool get _shouldCheckHealth => _isExpanded && _isAvailable == null;

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    _instructionsCtrl.dispose();
    super.dispose();
  }

  Future<void> _checkHealth() async {
    if (_isAvailable != null) return;
    final available = await _aiAssistService.checkAiHealth();
    if (mounted) {
      setState(() {
        _isAvailable = available;
      });
    }
  }

  Future<void> _handleAction(String action) async {
    if (!_isAvailable!) {
      _showSnackBar('خدمة الذكاء الاصطناعي غير متاحة');
      return;
    }

    final currentRequestId = ++_requestId;

    String? html;
    if (action != 'generate') {
      html = await widget.onGetHtml();
      final stripped = _stripHtmlTags(html);
      if (stripped.isEmpty) {
        _showSnackBar('يرجى إدخال نص أولاً');
        return;
      }
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final result = await _aiAssistService.documentExpert(
        action: action,
        htmlContent: html,
        targetLanguage: _selectedLanguage,
        instructions:
            _instructionsCtrl.text.isEmpty ? null : _instructionsCtrl.text,
      );

      if (!mounted) return;
      if (currentRequestId != _requestId) return;

      setState(() {
        _resultHtml = result;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      if (currentRequestId != _requestId) return;

      setState(() {
        _isLoading = false;
      });
      _showSnackBar(e.toString());
    }
  }

  String _stripHtmlTags(String html) {
    if (html.isEmpty) return '';
    var stripped = html
        .replaceAll(RegExp(r'<p><br></p>', caseSensitive: false), '')
        .replaceAll(RegExp(r'<p>&nbsp;</p>', caseSensitive: false), '')
        .replaceAll(RegExp(r'<br\s*/?>'), ' ')
        .replaceAll(RegExp(r'<[^>]*>'), '')
        .replaceAll(RegExp(r'&nbsp;'), ' ')
        .replaceAll(RegExp(r'&[a-z]+;'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return stripped;
  }

  void _showSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  void _applyResult() {
    if (_resultHtml == null) return;
    widget.onApplyHtml(_resultHtml!);
    setState(() {
      _resultHtml = null;
    });
    _showSnackBar('تم تطبيق النص بنجاح');
  }

  void _discardResult() {
    setState(() {
      _resultHtml = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.all(8),
      child: ExpansionTile(
        title: const Text(
          'مساعد الوثائق الذكي',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        initiallyExpanded: false,
        onExpansionChanged: (expanded) {
          setState(() {
            _isExpanded = expanded;
          });
          if (expanded && _isAvailable == null) {
            _checkHealth();
          }
        },
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _actionLabels.entries.map((entry) {
                    final isDisabled = _isAvailable == false;
                    return Tooltip(
                      message:
                          isDisabled ? 'خدمة الذكاء الاصطناعي غير متاحة' : '',
                      child: OutlinedButton(
                        onPressed:
                            isDisabled ? null : () => _handleAction(entry.key),
                        child: Text(entry.value),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    const Text('اللغة: '),
                    const SizedBox(width: 8),
                    SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(value: 'ar', label: Text('العربية')),
                        ButtonSegment(value: 'en', label: Text('English')),
                      ],
                      selected: {_selectedLanguage},
                      onSelectionChanged: (selection) {
                        setState(() {
                          _selectedLanguage = selection.first;
                        });
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _instructionsCtrl,
                  decoration: const InputDecoration(
                    labelText: 'تعليمات إضافية (اختياري)',
                    border: OutlineInputBorder(),
                    hintText: 'أدخل أي تعليمات خاصة أو ملاحظات',
                  ),
                  maxLines: 2,
                  maxLength: 1000,
                ),
                if (_isLoading) ...[
                  const SizedBox(height: 16),
                  const Center(child: CircularProgressIndicator()),
                ],
                if (_hasContent && !_isLoading) ...[
                  const SizedBox(height: 16),
                  const Text(
                    'النتيجة:',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.grey[100],
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.grey[300]!),
                    ),
                    child: SelectableText(
                      _stripHtmlTags(_resultHtml!),
                      textDirection: TextDirection.rtl,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      OutlinedButton(
                        onPressed: _discardResult,
                        child: const Text('تجاهل'),
                      ),
                      const SizedBox(width: 12),
                      FilledButton(
                        onPressed: _applyResult,
                        child: const Text('تطبيق'),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
