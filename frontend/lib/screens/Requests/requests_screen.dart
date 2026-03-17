import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/request_model.dart';
import '../../services/request_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/claude_widgets.dart';
import 'add_request_screen.dart';
import 'request_detail_screen.dart';

class RequestsScreen extends StatefulWidget {
  final String userRole;
  final VoidCallback? onChanged;
  const RequestsScreen({super.key, required this.userRole, this.onChanged});

  @override
  State<RequestsScreen> createState() => _RequestsScreenState();
}

class _RequestsScreenState extends State<RequestsScreen> {
  final _service = RequestService();
  List<RequestModel> _requests = [];
  String _statusFilter = 'All';
  bool _loading = true;

  // Selection mode (requester only)
  bool _selectionMode = false;
  final Set<String> _selectedIds = {};

  String get _email =>
      Supabase.instance.client.auth.currentUser?.email ?? '';

  bool get _canDelete =>
      widget.userRole == 'requester' ||
      widget.userRole == 'admin' ||
      widget.userRole == 'tech';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final data = await _service.fetchRequests(
      email: _email,
      userRole: widget.userRole,
    );
    if (!mounted) return;
    setState(() {
      _requests = data;
      _loading = false;
    });
    widget.onChanged?.call();
  }

  List<RequestModel> get _filtered {
    if (_statusFilter == 'All') return _requests;
    return _requests.where((r) => r.status == _statusFilter).toList();
  }

  void _enterSelectionMode(String id) {
    setState(() {
      _selectionMode = true;
      _selectedIds.add(id);
    });
  }

  void _toggleSelection(String id) {
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
        if (_selectedIds.isEmpty) _selectionMode = false;
      } else {
        _selectedIds.add(id);
      }
    });
  }

  void _exitSelectionMode() {
    setState(() {
      _selectionMode = false;
      _selectedIds.clear();
    });
  }

  Future<void> _deleteSelected() async {
    final count = _selectedIds.length;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.bgSurface,
        title: const Text('Delete Requests', style: TextStyle(color: AppColors.textPrimary)),
        content: Text(
          'Delete $count request${count > 1 ? 's' : ''}?',
          style: const TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Delete', style: TextStyle(color: Colors.red.shade400)),
          ),
        ],
      ),
    ) ?? false;

    if (!confirm || !mounted) return;

    final ids = List<String>.from(_selectedIds);
    _exitSelectionMode();
    final messenger = ScaffoldMessenger.of(context);
    try {
      for (final id in ids) {
        await _service.deleteRequest(id: id, email: _email, userRole: widget.userRole);
      }
      await _load();
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Failed to delete: $e')));
      if (mounted) await _load();
    }
  }

  Future<void> _deleteSingleRequest(RequestModel req) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.bgSurface,
        title: const Text('Delete Request', style: TextStyle(color: AppColors.textPrimary)),
        content: const Text(
          'Are you sure you want to delete this request?',
          style: TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Delete', style: TextStyle(color: Colors.red.shade400)),
          ),
        ],
      ),
    ) ?? false;

    if (!confirm || !mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    try {
      await _service.deleteRequest(id: req.id, email: _email, userRole: widget.userRole);
      await _load();
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Failed to delete: $e')));
      if (mounted) await _load();
    }
  }

  Future<void> _openAdd() async {
    final added = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const AddRequestScreen()),
    );
    if (added == true) await _load();
  }

  Future<void> _openDetail(RequestModel req) async {
    final updated = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => RequestDetailScreen(
          request: req,
          userRole: widget.userRole,
        ),
      ),
    );
    if (updated == true) await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgPrimary,
      body: SafeArea(
        child: Column(
          children: [
            // ── Header ──────────────────────────────────────────
            Container(
              color: AppColors.bgSurface,
              padding: const EdgeInsets.fromLTRB(8, 6, 8, 10),
              child: _selectionMode
                  ? _SelectionBar(
                      count: _selectedIds.length,
                      onCancel: _exitSelectionMode,
                      onDelete: _selectedIds.isNotEmpty ? _deleteSelected : null,
                    )
                  : Padding(
                      padding: const EdgeInsets.fromLTRB(8, 6, 8, 0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Requests',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textPrimary,
                              letterSpacing: -0.3,
                            ),
                          ),
                          const SizedBox(height: 12),
                          FilterChipRow(
                            filters: const ['All', 'Open', 'Closed'],
                            selected: _statusFilter,
                            onSelected: (s) => setState(() => _statusFilter = s),
                          ),
                        ],
                      ),
                    ),
            ),

            const Divider(height: 0, thickness: 0.5, color: AppColors.border),

            // ── List ────────────────────────────────────────────
            Expanded(
              child: _loading
                  ? const Center(
                      child: CircularProgressIndicator(
                        color: AppColors.accent,
                        strokeWidth: 1.5,
                      ),
                    )
                  : _filtered.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.inbox_outlined,
                                size: 48,
                                color: AppColors.bgSurface3,
                              ),
                              const SizedBox(height: 12),
                              Text(
                                _statusFilter == 'All'
                                    ? 'No requests yet'
                                    : 'No $_statusFilter requests',
                                style: const TextStyle(
                                  fontSize: 14,
                                  color: AppColors.textTertiary,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        )
                      : RefreshIndicator(
                          onRefresh: _load,
                          color: AppColors.accent,
                          child: ListView.separated(
                            padding: const EdgeInsets.fromLTRB(14, 12, 14, 80),
                            itemCount: _filtered.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 8),
                            itemBuilder: (_, i) {
                              final req = _filtered[i];

                              // Selection mode: show checkboxes, no swipe
                              if (_selectionMode) {
                                return _RequestCard(
                                  request: req,
                                  selectionMode: true,
                                  isSelected: _selectedIds.contains(req.id),
                                  onTap: () => _toggleSelection(req.id),
                                );
                              }

                              // Non-requester: no delete, no long press
                              if (!_canDelete) {
                                return _RequestCard(
                                  request: req,
                                  onTap: () => _openDetail(req),
                                );
                              }

                              // Requester: swipe to reveal delete + long press for multi-select
                              return _SwipeRevealCard(
                                onTap: () => _openDetail(req),
                                onLongPress: () => _enterSelectionMode(req.id),
                                onDelete: () => _deleteSingleRequest(req),
                                child: _RequestCard(request: req),
                              );
                            },
                          ),
                        ),
            ),
          ],
        ),
      ),
      floatingActionButton: (!_selectionMode && widget.userRole == 'requester')
          ? ClaudeFAB(onTap: _openAdd)
          : null,
    );
  }
}

// ── Selection bar ─────────────────────────────────────────────────────────────

class _SelectionBar extends StatelessWidget {
  final int count;
  final VoidCallback onCancel;
  final VoidCallback? onDelete;

  const _SelectionBar({required this.count, required this.onCancel, this.onDelete});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        IconButton(
          icon: const Icon(Icons.close_rounded, size: 20, color: AppColors.textPrimary),
          onPressed: onCancel,
          padding: const EdgeInsets.all(8),
        ),
        Expanded(
          child: Text(
            '$count selected',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
          ),
        ),
        if (onDelete != null)
          IconButton(
            icon: Icon(Icons.delete_outline_rounded, size: 22, color: Colors.red.shade400),
            onPressed: onDelete,
            padding: const EdgeInsets.all(8),
          ),
      ],
    );
  }
}

// ── Swipe Reveal Card ─────────────────────────────────────────────────────────

class _SwipeRevealCard extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final VoidCallback onDelete;

  const _SwipeRevealCard({
    required this.child,
    this.onTap,
    this.onLongPress,
    required this.onDelete,
  });

  @override
  State<_SwipeRevealCard> createState() => _SwipeRevealCardState();
}

class _SwipeRevealCardState extends State<_SwipeRevealCard>
    with SingleTickerProviderStateMixin {
  static const double _actionWidth = 72.0;
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 220));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  bool get _isOpen => _ctrl.value > 0.3;

  void _close() => _ctrl.animateTo(0, curve: Curves.easeOut);
  void _open() => _ctrl.animateTo(1, curve: Curves.easeOut);

  void _handleDragUpdate(DragUpdateDetails d) {
    _ctrl.value = (_ctrl.value - d.delta.dx / _actionWidth).clamp(0.0, 1.0);
  }

  void _handleDragEnd(DragEndDetails d) {
    if (_ctrl.value > 0.5 || (d.primaryVelocity ?? 0) < -300) {
      _open();
    } else {
      _close();
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _isOpen ? _close() : widget.onTap?.call(),
      onLongPress: () { if (!_isOpen) widget.onLongPress?.call(); },
      onHorizontalDragUpdate: _handleDragUpdate,
      onHorizontalDragEnd: _handleDragEnd,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: AnimatedBuilder(
          animation: _ctrl,
          builder: (_, child) => Stack(
            children: [
              Positioned.fill(
                child: Container(
                  color: AppColors.bgPrimary,
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.only(right: 10),
                  child: GestureDetector(
                    onTap: () { _close(); widget.onDelete(); },
                    child: Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        color: Colors.red.shade600,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.delete_outline_rounded,
                        color: Colors.white,
                        size: 22,
                      ),
                    ),
                  ),
                ),
              ),
              Transform.translate(
                offset: Offset(-_ctrl.value * _actionWidth, 0),
                child: child,
              ),
            ],
          ),
          child: widget.child,
        ),
      ),
    );
  }
}

// ── Request Card ──────────────────────────────────────────────────────────────

class _RequestCard extends StatelessWidget {
  final RequestModel request;
  final VoidCallback? onTap;
  final bool selectionMode;
  final bool isSelected;

  const _RequestCard({
    required this.request,
    this.onTap,
    this.selectionMode = false,
    this.isSelected = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.accentBg : AppColors.bgSurface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? AppColors.accent : AppColors.border,
            width: isSelected ? 1.5 : 0.5,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (selectionMode)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: Checkbox(
                        value: isSelected,
                        onChanged: (_) => onTap?.call(),
                        activeColor: AppColors.accent,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        visualDensity: VisualDensity.compact,
                        side: const BorderSide(color: AppColors.border2, width: 1.5),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                      ),
                    ),
                  ),
                Expanded(
                  child: Text(
                    request.title,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                _StatusBadge(status: request.status),
              ],
            ),

            if (request.description.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                request.description,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
              ),
            ],

            const SizedBox(height: 10),

            Row(
              children: [
                if (request.location.isNotEmpty) ...[
                  const Icon(Icons.location_on_outlined,
                      size: 12, color: AppColors.textTertiary),
                  const SizedBox(width: 3),
                  Text(
                    request.location,
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.textTertiary,
                    ),
                  ),
                  const SizedBox(width: 10),
                ],
                const Icon(Icons.person_outline_rounded,
                    size: 12, color: AppColors.textTertiary),
                const SizedBox(width: 3),
                Text(
                  request.requesterName,
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textTertiary,
                  ),
                ),
                const Spacer(),
                Text(
                  _formatDate(request.createdAt),
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textTertiary,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime dt) {
    return '${dt.day}/${dt.month}/${dt.year}';
  }
}

// ── Status Badge ──────────────────────────────────────────────────────────────

class _StatusBadge extends StatelessWidget {
  final String status;
  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    final isOpen = status == 'Open';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: isOpen ? AppColors.pendingBg : AppColors.closedBg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        status,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w500,
          color: isOpen ? AppColors.pendingText : AppColors.closedText,
        ),
      ),
    );
  }
}
