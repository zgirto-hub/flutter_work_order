import 'dart:js_interop';
import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import '../../widgets/claude_widgets.dart';
import '../../theme/app_theme.dart';
import '../../widgets/claude_widgets.dart';
import 'package:web/web.dart' as web;
import '../../models/generated_letter.dart';
import '../../services/letter_service.dart';
import '../Files/file_viewer_screen.dart';

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
      final letters = await LetterService().fetchAllV2();
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
            child: const Text('Delete', style: TextStyle(color: AppColors.dangerText)),
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
      final bytes = await LetterService().regenerateV2(letterId);
      if (!mounted) return;
      final blob = web.Blob(
        <JSAny>[bytes.toJS].toJS,
        web.BlobPropertyBag(type: 'application/pdf'),
      );
      final blobUrl = web.URL.createObjectURL(blob);
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => FileViewerScreen(
            fileUrl: blobUrl,
            fileName: 'letter_$letterId.pdf',
          ),
        ),
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
      builder: (ctx) {
        final viewInsets = MediaQuery.of(ctx).viewInsets;
        return DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        maxChildSize: 0.9,
        builder: (_, scrollCtrl) => Directionality(
          textDirection: TextDirection.rtl,
          child: ListView(
            controller: scrollCtrl,
            padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + viewInsets.bottom),
            children: [
              // Handle bar
              Center(
                child: Container(
                  width: 40, height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: AppColors.border,
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
                      onPressed: () async {
                        Navigator.pop(context);
                        if (letter.id != null) {
                          try {
                            final full = await LetterService().fetchOneV2(letter.id!);
                            widget.onEditLetter?.call(full);
                          } catch (_) {
                            widget.onEditLetter?.call(letter);
                          }
                        } else {
                          widget.onEditLetter?.call(letter);
                        }
                      },
                      icon: const Icon(Icons.edit),
                      label: const Text('Edit'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        Navigator.pop(context);
                        GeneratedLetter source = letter;
                        if (letter.id != null) {
                          try {
                            source = await LetterService().fetchOneV2(letter.id!);
                          } catch (_) {}
                        }
                        widget.onEditLetter?.call(source.asCopy());
                      },
                      icon: const Icon(Icons.copy),
                      label: const Text('Copy'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: letter.id != null
                          ? () => _regeneratePdf(letter.id!)
                          : null,
                      icon: const Icon(Icons.picture_as_pdf),
                      label: const Text('PDF'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.accent,
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
                      label: const Text('Delete', style: TextStyle(color: AppColors.dangerText)),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: AppColors.dangerBorder),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
      },
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
      return const Center(child: CircularProgressIndicator(color: AppColors.accent));
    }
    if (_letters.isEmpty) {
      return EmptyState(
        icon: Icons.mail_outline,
        title: 'No Letters Yet',
        subtitle: 'Letters you create will appear here',
      );
    }
    return RefreshIndicator(color: AppColors.accent,
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
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: AppColors.textPrimary),
              ),
              subtitle: Text('${letter.alsayed} — ${letter.tarikh}', style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
              trailing: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (letter.createdAt != null)
                    Text(
                      '${letter.createdAt!.day}/${letter.createdAt!.month}/${letter.createdAt!.year}',
                      style: TextStyle(fontSize: 11, color: AppColors.textTertiary),
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
