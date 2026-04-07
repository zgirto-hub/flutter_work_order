import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import '../../models/generated_letter.dart';
import '../../services/letter_service.dart';

class LetterHistoryTabV2 extends StatefulWidget {
  final void Function(GeneratedLetter letter)? onEditLetter;

  const LetterHistoryTabV2({super.key, this.onEditLetter});

  @override
  State<LetterHistoryTabV2> createState() => _LetterHistoryTabV2State();
}

class _LetterHistoryTabV2State extends State<LetterHistoryTabV2> {
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
      if (mounted) setState(() { _letters = letters; _isLoading = false; });
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading letters: $e')),
        );
      }
    }
  }

  Future<void> _deleteLetter(String letterId, BuildContext ctx) async {
    final confirm = await showDialog<bool>(
      context: ctx,
      builder: (c) => AlertDialog(
        title: const Text('Delete Letter'),
        content: const Text('Are you sure you want to delete this letter?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await LetterService().delete(letterId);
      if (mounted) {
        Navigator.pop(ctx);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Letter deleted')),
        );
        _loadLetters();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  Future<void> _regeneratePdf(String letterId) async {
    try {
      final bytes = await LetterService().regenerate(letterId);
      await Printing.sharePdf(
        bytes: bytes,
        filename: 'letter_$letterId.pdf',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  void _showLetterDetail(GeneratedLetter letter) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        maxChildSize: 0.9,
        builder: (_, scrollCtrl) => Directionality(
          textDirection: TextDirection.rtl,
          child: ListView(
            controller: scrollCtrl,
            padding: const EdgeInsets.all(20),
            children: [
              // Handle bar
              Center(
                child: Container(
                  width: 40, height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Text('Letter Details',
                  style: Theme.of(ctx).textTheme.titleLarge),
              const SizedBox(height: 16),
              _row('Reference', letter.ishara),
              _row('Date', letter.tarikh),
              _row('Recipient', letter.alsayed),
              _row('Subject', letter.almawdoo),
              _row('Signer', letter.alasm),
              const Divider(height: 24),

              // Linked payment certificates
              if (letter.paymentCertificates.isNotEmpty) ...[
                Text('Linked Payment Certificates',
                    style: Theme.of(ctx).textTheme.titleSmall),
                const SizedBox(height: 8),
                ...letter.paymentCertificates.map((cert) => Card(
                      child: ListTile(
                        leading: const Icon(Icons.receipt_long),
                        title: Text(cert.certificateNumber),
                        subtitle: Text(cert.subject),
                      ),
                    )),
                const SizedBox(height: 16),
              ],

              // Action buttons
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Navigator.pop(context);
                        widget.onEditLetter?.call(letter);
                      },
                      icon: const Icon(Icons.edit),
                      label: const Text('Edit'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: letter.id != null
                          ? () => _regeneratePdf(letter.id!)
                          : null,
                      icon: const Icon(Icons.picture_as_pdf),
                      label: const Text('PDF'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFCC0000),
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: letter.id != null
                          ? () => _deleteLetter(letter.id!, context)
                          : null,
                      icon: const Icon(Icons.delete_outline, color: Colors.red),
                      label: const Text('Delete', style: TextStyle(color: Colors.red)),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Colors.red),
                      ),
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

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(label,
                style: const TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 13)),
          ),
          Expanded(
            child: Text(value, style: const TextStyle(fontSize: 13)),
          ),
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
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.mail_outline, size: 48, color: Colors.grey),
            SizedBox(height: 12),
            Text('No previous letters',
                style: TextStyle(color: Colors.grey, fontSize: 15)),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _loadLetters,
      child: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: _letters.length,
        itemBuilder: (ctx, i) {
          final letter = _letters[i];
          return Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              title: Text(
                letter.almawdoo,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              subtitle: Text('${letter.alsayed} — ${letter.tarikh}'),
              trailing: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (letter.createdAt != null)
                    Text(
                      '${letter.createdAt!.day}/${letter.createdAt!.month}/${letter.createdAt!.year}',
                      style: const TextStyle(fontSize: 11, color: Colors.grey),
                    ),
                  if (letter.paymentCertificates.isNotEmpty)
                    Chip(
                      label: Text(
                        '${letter.paymentCertificates.length} certs',
                        style: const TextStyle(fontSize: 10),
                      ),
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                    ),
                ],
              ),
              onTap: () => _showLetterDetail(letter),
            ),
          );
        },
      ),
    );
  }
}
