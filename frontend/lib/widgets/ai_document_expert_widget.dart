import 'package:flutter/material.dart';
import '../services/ai_assist_service.dart';

class _ActionItem {
  final String key;
  final String label;
  final IconData icon;
  final Color color;

  const _ActionItem(this.key, this.label, this.icon, this.color);
}

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

  static final List<_ActionItem> _actions = [
    const _ActionItem('improve', 'تحسين وتنسيق', Icons.auto_fix_high, Color(0xFF2196F3)),
    const _ActionItem('correct', 'تصحيح نحوي', Icons.spellcheck, Color(0xFF4CAF50)),
    const _ActionItem('generate', 'توليد من ملاحظات', Icons.note_add, Color(0xFF9C27B0)),
    const _ActionItem('translate', 'ترجمة', Icons.translate, Color(0xFFFF9800)),
    const _ActionItem('concise', 'تلخيص', Icons.compress, Color(0xFF00BCD4)),
    const _ActionItem('elaborate', 'توسيع', Icons.expand, Color(0xFFE91E63)),
    const _ActionItem('custom', 'تعليمات مخصصة', Icons.tune, Color(0xFF607D8B)),
  ];

  String _selectedLanguage = 'ar';

  bool get _hasContent {
    return _resultHtml != null && _resultHtml!.isNotEmpty;
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

    if (action == 'custom') {
      if (_instructionsCtrl.text.trim().isEmpty) {
        _showSnackBar('يرجى إدخال التعليمات أولاً');
        return;
      }
    }

    final currentRequestId = ++_requestId;

    String? html;
    if (action == 'custom') {
      html = await widget.onGetHtml();
    } else if (action != 'generate') {
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

  Widget _buildActionButton(_ActionItem item) {
    final isDisabled = _isAvailable == false;
    final isActive = _isLoading;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: isDisabled || isActive ? null : () => _handleAction(item.key),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: isDisabled
                ? Colors.grey.shade100
                : item.color.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isDisabled
                  ? Colors.grey.shade300
                  : item.color.withValues(alpha: 0.3),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                item.icon,
                size: 14,
                color: isDisabled ? Colors.grey.shade400 : item.color,
              ),
              const SizedBox(width: 4),
              Text(
                item.label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: isDisabled ? Colors.grey.shade400 : item.color.withValues(alpha: 0.9),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.all(8),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: ExpansionTile(
        title: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.smart_toy_outlined, color: Color(0xFF9C27B0), size: 20),
            SizedBox(width: 8),
            Text(
              'AI Document Expert',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
            ),
          ],
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
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _actions.map((item) => _buildActionButton(item)).toList(),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Icon(Icons.language, size: 16, color: Colors.grey.shade600),
                    const SizedBox(width: 4),
                    Text('اللغة:', style: TextStyle(fontSize: 12, color: Colors.grey.shade700, fontWeight: FontWeight.w600)),
                    const SizedBox(width: 8),
                    ChoiceChip(
                      label: const Text('العربية', style: TextStyle(fontSize: 11)),
                      selected: _selectedLanguage == 'ar',
                      onSelected: (_) => setState(() => _selectedLanguage = 'ar'),
                      visualDensity: VisualDensity.compact,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    const SizedBox(width: 6),
                    ChoiceChip(
                      label: const Text('English', style: TextStyle(fontSize: 11)),
                      selected: _selectedLanguage == 'en',
                      onSelected: (_) => setState(() => _selectedLanguage = 'en'),
                      visualDensity: VisualDensity.compact,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _instructionsCtrl,
                  decoration: InputDecoration(
                    labelText: 'تعليمات إضافية (اختياري)',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    hintText: 'أدخل أي تعليمات خاصة أو ملاحظات',
                    prefixIcon: const Icon(Icons.edit_note),
                    filled: true,
                    fillColor: Colors.grey.shade50,
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
                      OutlinedButton.icon(
                        onPressed: _discardResult,
                        icon: const Icon(Icons.close, size: 18),
                        label: const Text('تجاهل'),
                      ),
                      const SizedBox(width: 12),
                      FilledButton.icon(
                        onPressed: _applyResult,
                        icon: const Icon(Icons.check, size: 18),
                        label: const Text('تطبيق'),
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
