import 'package:flutter/material.dart';
import '../../models/generated_letter.dart';
import '../../services/letter_service.dart';
import '../../services/activity_log_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/claude_widgets.dart';
import 'letter_html_viewer_screen.dart';

class LetterHistoryTabV2 extends StatefulWidget {
  final void Function(GeneratedLetter letter)? onEditLetter;

  const LetterHistoryTabV2({super.key, this.onEditLetter});

  @override
  State<LetterHistoryTabV2> createState() => _LetterHistoryTabV2State();
}

class _LetterHistoryTabV2State extends State<LetterHistoryTabV2> {
  List<GeneratedLetter> _letters = [];
  bool _isLoading = true;
  int _expandedIndex = -1;
  bool _actionInProgress = false;

  @override
  void initState() {
    super.initState();
    _loadLetters();
  }

  Future<void> _loadLetters() async {
    try {
      final letters = await LetterService().fetchAllV2();
      if (mounted)
        setState(() {
          _letters = letters;
          _isLoading = false;
        });
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading letters: $e')),
        );
      }
    }
  }

  Future<void> _deleteLetter(String letterId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: AppColors.bgSurface,
        title: Text('Delete Letter',
            style: TextStyle(color: AppColors.textPrimary)),
        content: Text('Are you sure you want to delete this letter?',
            style: TextStyle(color: AppColors.textSecondary)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            child:
                Text('Delete', style: TextStyle(color: AppColors.dangerText)),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await LetterService().delete(letterId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Letter deleted')),
        );
        setState(() => _expandedIndex = -1);
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

  Future<void> _previewLetter(String letterId) async {
    try {
      final html = await LetterService().previewHtmlById(letterId);
      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => LetterHtmlViewerScreen(
            title: 'Letter Preview',
            html: html,
            onShare: () async {
              ActivityLogService().logShared(
                documentType: 'letter',
                documentId: letterId,
              );
              return await LetterService().regenerateV2(letterId);
            },
            shareFileName:
                'letter_${letterId.substring(0, letterId.length < 8 ? letterId.length : 8)}.pdf',
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

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Center(child: CircularProgressIndicator(color: AppColors.accent));
    }
    if (_letters.isEmpty) {
      return EmptyState(
        icon: Icons.mail_outline,
        title: 'No Letters Yet',
        subtitle: 'Letters you create will appear here',
      );
    }
    return RefreshIndicator(
      color: AppColors.accent,
      onRefresh: _loadLetters,
      child: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: _letters.length,
        itemBuilder: (ctx, i) {
          final letter = _letters[i];
          final expanded = _expandedIndex == i;
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _LetterCard(
              letter: letter,
              expanded: expanded,
              onTap: () {
                setState(() {
                  _expandedIndex = expanded ? -1 : i;
                });
              },
              onEdit: () async {
                if (_actionInProgress) return;
                _actionInProgress = true;
                try {
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
                } finally {
                  _actionInProgress = false;
                }
              },
              onCopy: () async {
                if (_actionInProgress) return;
                _actionInProgress = true;
                try {
                  GeneratedLetter source = letter;
                  if (letter.id != null) {
                    try {
                      source = await LetterService().fetchOneV2(letter.id!);
                    } catch (_) {}
                  }
                  widget.onEditLetter?.call(source.asCopy());
                } finally {
                  _actionInProgress = false;
                }
              },
              bodyText: letter.bodyPreview,
              onPdf: letter.id != null
                  ? () {
                      if (_actionInProgress) return;
                      _actionInProgress = true;
                      _previewLetter(letter.id!)
                          .whenComplete(() => _actionInProgress = false);
                    }
                  : null,
              onDelete: letter.id != null
                  ? () {
                      if (_actionInProgress) return;
                      _actionInProgress = true;
                      _deleteLetter(letter.id!)
                          .whenComplete(() => _actionInProgress = false);
                    }
                  : null,
            ),
          );
        },
      ),
    );
  }
}

// ─── Expandable Letter Card ──────────────────────────────────────────────────

class _LetterCard extends StatefulWidget {
  final GeneratedLetter letter;
  final bool expanded;
  final String? bodyText;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onCopy;
  final VoidCallback? onPdf;
  final VoidCallback? onDelete;

  const _LetterCard({
    required this.letter,
    required this.expanded,
    this.bodyText,
    required this.onTap,
    required this.onEdit,
    required this.onCopy,
    this.onPdf,
    this.onDelete,
  });

  @override
  State<_LetterCard> createState() => _LetterCardState();
}

class _LetterCardState extends State<_LetterCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 240),
    value: widget.expanded ? 1.0 : 0.0,
  );

  late final Animation<double> _size =
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOutCubic);
  late final Animation<double> _fade =
      CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
  late final Animation<double> _chevron =
      Tween<double>(begin: 0.0, end: 0.5).animate(
    CurvedAnimation(parent: _ctrl, curve: Curves.easeInOutCubic),
  );

  @override
  void didUpdateWidget(_LetterCard old) {
    super.didUpdateWidget(old);
    if (old.expanded != widget.expanded) {
      widget.expanded ? _ctrl.forward() : _ctrl.reverse();
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final letter = widget.letter;

    return GestureDetector(
      onTap: widget.onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          color: AppColors.bgSurface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: widget.expanded ? AppColors.border2 : AppColors.border,
            width: 0.5,
          ),
        ),
        child: Column(
          children: [
            // ── Main Row ─────────────────────────────────────
            Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Content
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Top row: reference + date
                        Row(
                          children: [
                            if (letter.ishara.isNotEmpty)
                              Text(
                                letter.ishara,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500,
                                  color: AppColors.textTertiary,
                                  letterSpacing: 0.03,
                                ),
                              ),
                            if (letter.paymentCertificates.isNotEmpty) ...[
                              SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 1),
                                decoration: BoxDecoration(
                                  color: AppColors.bgSurface2,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                      color: AppColors.border2, width: 0.5),
                                ),
                                child: Text(
                                  '${letter.paymentCertificates.length} certs',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w500,
                                    color: AppColors.textTertiary,
                                  ),
                                ),
                              ),
                            ],
                            const Spacer(),
                            if (letter.createdAt != null)
                              Text(
                                '${letter.createdAt!.day}/${letter.createdAt!.month}/${letter.createdAt!.year}',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: AppColors.textTertiary,
                                ),
                              ),
                          ],
                        ),

                        SizedBox(height: 5),

                        // Subject (title)
                        Text(
                          letter.almawdoo,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: AppColors.textPrimary,
                            height: 1.4,
                          ),
                          maxLines: widget.expanded ? null : 1,
                          overflow:
                              widget.expanded ? null : TextOverflow.ellipsis,
                        ),

                        SizedBox(height: 3),

                        // Recipient
                        Text(
                          letter.alsayed,
                          style: TextStyle(
                            fontSize: 11,
                            color: AppColors.textSecondary,
                            height: 1.4,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),

                  // Chevron
                  Padding(
                    padding: const EdgeInsets.only(top: 2, left: 8),
                    child: AnimatedBuilder(
                      animation: _chevron,
                      builder: (_, child) => Transform.rotate(
                        angle: _chevron.value * 3.14159265,
                        child: child,
                      ),
                      child: Icon(
                        Icons.keyboard_arrow_down_rounded,
                        size: 18,
                        color: AppColors.textTertiary,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // ── Expanded Section ─────────────────────────────
            SizeTransition(
              sizeFactor: _size,
              axisAlignment: -1,
              child: FadeTransition(
                opacity: _fade,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                  decoration: BoxDecoration(
                    color: AppColors.bgSurface2,
                    borderRadius:
                        BorderRadius.vertical(bottom: Radius.circular(14)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Letter body preview
                      if (widget.bodyText != null &&
                          widget.bodyText!.isNotEmpty) ...[
                        Text(
                          _stripHtml(widget.bodyText!),
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                            height: 1.5,
                          ),
                          maxLines: 4,
                          overflow: TextOverflow.ellipsis,
                        ),
                        SizedBox(height: 10),
                      ],

                      // Details
                      if (letter.tarikh.isNotEmpty)
                        _detailRow('Date', letter.tarikh),
                      if (letter.alasm.isNotEmpty)
                        _detailRow('Signer', letter.alasm),
                      if (letter.signerTitle.isNotEmpty)
                        _detailRow('Title', letter.signerTitle),

                      // Linked certs
                      if (letter.paymentCertificates.isNotEmpty) ...[
                        SizedBox(height: 8),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: letter.paymentCertificates.map((cert) {
                            return Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: AppColors.bgSurface,
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                    color: AppColors.border2, width: 0.5),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.receipt_long,
                                      size: 12, color: AppColors.textTertiary),
                                  SizedBox(width: 5),
                                  Text(cert.certificateNumber,
                                      style: TextStyle(
                                          fontSize: 11,
                                          color: AppColors.textSecondary,
                                          fontWeight: FontWeight.w500)),
                                ],
                              ),
                            );
                          }).toList(),
                        ),
                      ],

                      SizedBox(height: 10),

                      // Action buttons
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          _actionButton(
                            icon: Icons.picture_as_pdf_outlined,
                            label: 'PDF',
                            onTap: widget.onPdf,
                          ),
                          SizedBox(width: 8),
                          _actionButton(
                            icon: Icons.copy_outlined,
                            label: 'Copy',
                            onTap: widget.onCopy,
                          ),
                          SizedBox(width: 8),
                          _actionButton(
                            icon: Icons.edit_outlined,
                            label: 'Edit',
                            onTap: widget.onEdit,
                          ),
                          SizedBox(width: 8),
                          _actionButton(
                            icon: Icons.delete_outline,
                            label: 'Delete',
                            onTap: widget.onDelete,
                            danger: true,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _stripHtml(String html) {
    return html
        .replaceAll(RegExp(r'<br\s*/?>'), '\n')
        .replaceAll(RegExp(r'<[^>]*>'), '')
        .replaceAll(RegExp(r'&nbsp;'), ' ')
        .replaceAll(RegExp(r'&amp;'), '&')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trim();
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 60,
            child: Text(label,
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: AppColors.textTertiary)),
          ),
          Expanded(
            child: Text(value,
                style: TextStyle(fontSize: 11, color: AppColors.textSecondary)),
          ),
        ],
      ),
    );
  }

  Widget _actionButton({
    required IconData icon,
    required String label,
    VoidCallback? onTap,
    bool danger = false,
  }) {
    final color = danger ? AppColors.dangerText : AppColors.textSecondary;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: AppColors.bgSurface,
          borderRadius: BorderRadius.circular(9),
          border: Border.all(
            color: danger ? AppColors.dangerBorder : AppColors.border2,
            width: 0.5,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: color),
            SizedBox(width: 5),
            Text(label,
                style: TextStyle(
                    fontSize: 12, color: color, fontWeight: FontWeight.w500)),
          ],
        ),
      ),
    );
  }
}
