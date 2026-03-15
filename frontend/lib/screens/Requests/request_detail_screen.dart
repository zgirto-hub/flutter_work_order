import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/request_model.dart';
import '../../services/request_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/claude_widgets.dart';
import 'add_request_screen.dart';

class RequestDetailScreen extends StatefulWidget {
  final RequestModel request;
  final String userRole;

  const RequestDetailScreen({
    super.key,
    required this.request,
    required this.userRole,
  });

  @override
  State<RequestDetailScreen> createState() => _RequestDetailScreenState();
}

class _RequestDetailScreenState extends State<RequestDetailScreen> {
  final _service = RequestService();
  bool _closing = false;

  String get _email =>
      Supabase.instance.client.auth.currentUser?.email ?? '';

  bool get _canClose =>
      (widget.userRole == 'tech' || widget.userRole == 'admin') &&
      widget.request.status == 'Open';

  bool get _canEdit =>
      widget.userRole == 'requester' && widget.request.status == 'Open';

  Future<void> _openEdit() async {
    final updated = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => AddRequestScreen(request: widget.request),
      ),
    );
    if (updated == true && mounted) Navigator.pop(context, true);
  }

  Future<void> _closeRequest() async {
    final notesCtrl = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.bgSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Text(
          'Close Request',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Mark this request as resolved?',
              style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 12),
            Container(
              decoration: BoxDecoration(
                color: AppColors.bgSurface2,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.border, width: 0.5),
              ),
              child: TextField(
                controller: notesCtrl,
                maxLines: 3,
                style: const TextStyle(
                    fontSize: 13, color: AppColors.textPrimary),
                decoration: const InputDecoration(
                  hintText: 'Add a note (optional)',
                  hintStyle: TextStyle(
                      fontSize: 13, color: AppColors.textTertiary),
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.all(10),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.accent,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('Close Request',
                style: TextStyle(fontSize: 13)),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _closing = true);
    try {
      await _service.closeRequest(
        id: widget.request.id,
        closedBy: _email,
        techNotes: notesCtrl.text.trim().isEmpty
            ? null
            : notesCtrl.text.trim(),
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to close: $e'),
          backgroundColor: AppColors.dangerText,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _closing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final req = widget.request;
    final isOpen = req.status == 'Open';

    return Scaffold(
      backgroundColor: AppColors.bgPrimary,
      body: SafeArea(
        child: Column(
          children: [
            // ── Header ──────────────────────────────────────────
            Container(
              color: AppColors.bgSurface,
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: AppColors.bgSurface2,
                        borderRadius: BorderRadius.circular(9),
                        border: Border.all(
                            color: AppColors.border2, width: 0.5),
                      ),
                      child: const Icon(Icons.arrow_back_rounded,
                          size: 16, color: AppColors.textSecondary),
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Request Detail',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                        letterSpacing: -0.3,
                      ),
                    ),
                  ),
                  if (_canEdit) ...[
                    GestureDetector(
                      onTap: _openEdit,
                      child: Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: AppColors.bgSurface2,
                          borderRadius: BorderRadius.circular(9),
                          border: Border.all(color: AppColors.border2, width: 0.5),
                        ),
                        child: const Icon(Icons.edit_outlined,
                            size: 16, color: AppColors.textSecondary),
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  _StatusPill(status: req.status),
                ],
              ),
            ),

            const Divider(height: 0, thickness: 0.5, color: AppColors.border),

            // ── Content ─────────────────────────────────────────
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Title
                    SurfaceCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            req.title,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          if (req.description.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Text(
                              req.description,
                              style: const TextStyle(
                                fontSize: 13,
                                color: AppColors.textSecondary,
                                height: 1.5,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),

                    const SizedBox(height: 12),

                    // Meta info
                    SectionLabel(text: 'Requester info'),
                    SurfaceCard(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      child: Column(
                        children: [
                          _InfoRow(
                            icon: Icons.person_outline_rounded,
                            label: 'Name',
                            value: req.requesterName,
                          ),
                          if (req.location.isNotEmpty)
                            _InfoRow(
                              icon: Icons.location_on_outlined,
                              label: 'Location',
                              value: req.location,
                              showDivider: false,
                            )
                          else
                            _InfoRow(
                              icon: Icons.email_outlined,
                              label: 'Email',
                              value: req.createdBy,
                              showDivider: false,
                            ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 12),

                    SectionLabel(text: 'Timeline'),
                    SurfaceCard(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      child: Column(
                        children: [
                          _InfoRow(
                            icon: Icons.calendar_today_outlined,
                            label: 'Submitted',
                            value: _formatDate(req.createdAt),
                            showDivider: !isOpen,
                          ),
                          if (!isOpen && req.closedAt != null) ...[
                            _InfoRow(
                              icon: Icons.check_circle_outline_rounded,
                              label: 'Closed',
                              value: _formatDate(req.closedAt!),
                              showDivider: req.closedBy != null,
                            ),
                            if (req.closedBy != null)
                              _InfoRow(
                                icon: Icons.engineering_outlined,
                                label: 'Closed by',
                                value: req.closedBy!.split('@').first,
                                showDivider: false,
                              ),
                          ],
                        ],
                      ),
                    ),

                    // Tech notes (if closed)
                    if (!isOpen && req.techNotes != null &&
                        req.techNotes!.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      SectionLabel(text: 'Tech notes'),
                      SurfaceCard(
                        child: Text(
                          req.techNotes!,
                          style: const TextStyle(
                            fontSize: 13,
                            color: AppColors.textSecondary,
                            height: 1.5,
                          ),
                        ),
                      ),
                    ],

                    // Close button (tech/admin only, open requests)
                    if (_canClose) ...[
                      const SizedBox(height: 24),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: _closing ? null : _closeRequest,
                          icon: _closing
                              ? const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 1.5,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(
                                  Icons.check_circle_outline_rounded,
                                  size: 16),
                          label: const Text('Close Request',
                              style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.accent,
                            foregroundColor: Colors.white,
                            padding:
                                const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10)),
                            elevation: 0,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime dt) =>
      '${dt.day}/${dt.month}/${dt.year}  ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
}

// ── Widgets ───────────────────────────────────────────────────────────────────

class _StatusPill extends StatelessWidget {
  final String status;
  const _StatusPill({required this.status});

  @override
  Widget build(BuildContext context) {
    final isOpen = status == 'Open';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: isOpen ? AppColors.pendingBg : AppColors.closedBg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        status,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w500,
          color: isOpen ? AppColors.pendingText : AppColors.closedText,
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final bool showDivider;

  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
    this.showDivider = true,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 11),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: AppColors.bgSurface2,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, size: 15, color: AppColors.textSecondary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
        if (showDivider)
          const Divider(height: 0, thickness: 0.5, color: AppColors.border),
      ],
    );
  }
}
