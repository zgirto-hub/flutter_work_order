import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import '../../models/generated_letter.dart';
import '../../services/letter_service.dart';
import '../../theme/app_theme.dart';

class LetterHistoryTab extends StatefulWidget {
  final void Function(GeneratedLetter letter)? onEditLetter;

  const LetterHistoryTab({super.key, this.onEditLetter});

  @override
  State<LetterHistoryTab> createState() => _LetterHistoryTabState();
}

class _LetterHistoryTabState extends State<LetterHistoryTab> {
  List<GeneratedLetter> _letters = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadLetters();
  }

  Future<void> _loadLetters() async {
    try {
      final letters = await LetterService().fetchAll();
      if (mounted) {
        setState(() {
          _letters = letters;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ: $e')),
        );
      }
    }
  }

  String _formatDate(DateTime? d) {
    if (d == null) return '';
    return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
  }

  Future<void> _regeneratePdf(GeneratedLetter letter) async {
    if (letter.id == null) return;
    try {
      final pdfBytes = await LetterService().regenerate(letter.id!);
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      await Printing.sharePdf(
          bytes: pdfBytes, filename: 'letter_$timestamp.pdf');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم إعادة توليد الخطاب')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ: $e')),
        );
      }
    }
  }

  void _showLetterDetail(GeneratedLetter letter) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        insetPadding: const EdgeInsets.all(16),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 500, maxHeight: 600),
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('تفاصيل الخطاب',
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
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _detailRow('الإشارة', letter.ishara),
                      _detailRow('التاريخ', letter.tarikh),
                      _detailRow('السيد', letter.alsayed),
                      _detailRow('الموضوع', letter.almawdoo),
                      _detailRow('النص', letter.bodyText),
                      _detailRow('الاسم', letter.alasm),
                      if (letter.createdAt != null)
                        _detailRow(
                            'تاريخ الإنشاء', _formatDate(letter.createdAt)),
                      if (letter.paymentCertificates.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        const Text('شهادات الدفع المرتبطة:',
                            style: TextStyle(fontWeight: FontWeight.bold)),
                        ...letter.paymentCertificates.map((cert) => Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                  '- ${cert['certificate_number']}: ${cert['subject']}'),
                            )),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Navigator.pop(context);
                        widget.onEditLetter?.call(letter);
                      },
                      icon: const Icon(Icons.edit),
                      label: const Text('تعديل'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _regeneratePdf(letter),
                      icon: const Icon(Icons.picture_as_pdf),
                      label: const Text('توليد PDF'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text('$label:',
                style: const TextStyle(fontWeight: FontWeight.bold)),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_letters.isEmpty) {
      return const Center(child: Text('لا توجد خطابات سابقة'));
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _letters.length,
      itemBuilder: (context, index) {
        final letter = _letters[index];
        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: ListTile(
            title: Text(
              letter.almawdoo,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: Text('${letter.alsayed} — ${letter.tarikh}'),
            trailing: letter.paymentCertificates.isNotEmpty
                ? Chip(
                    label: Text('${letter.paymentCertificates.length} شهادات'),
                    backgroundColor: AppColors.accent.withValues(alpha: 0.1),
                  )
                : null,
            onTap: () => _showLetterDetail(letter),
          ),
        );
      },
    );
  }
}
