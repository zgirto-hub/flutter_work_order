import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/app_notification.dart';
import '../../models/request_model.dart';
import '../../models/work_order.dart';
import '../../services/notification_service.dart';
import '../../services/request_service.dart';
import '../../services/work_order_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/claude_widgets.dart';
import '../Work_Orders/add_work_order.dart';
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
  final _woService = WorkOrderService();
  final _notificationService = NotificationService();
  List<RequestModel> _requests = [];
  Map<String, WorkOrder> _linkedByRequestId = {};
  List<AppNotification> _unreadNotifications = [];
  Map<String, int> _unreadByRequestId = {};
  String _statusFilter = 'All';
  bool _loading = true;
  String? _expandedRequestId;

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
    final workOrders = await _woService.fetchWorkOrders();
    final unread = await _notificationService.fetchNotifications(
      unreadOnly: true,
      limit: 300,
    );
    final linked = <String, WorkOrder>{};
    for (final wo in workOrders) {
      final reqId = wo.requestId;
      if (reqId != null && reqId.isNotEmpty) {
        linked[reqId] = wo;
      }
    }
    final unreadByRequest = _computeUnreadByRequest(unread, linked);
    if (!mounted) return;
    setState(() {
      _requests = data;
      _linkedByRequestId = linked;
      _unreadNotifications = unread;
      _unreadByRequestId = unreadByRequest;
      if (_expandedRequestId != null &&
          !_requests.any((r) => r.id == _expandedRequestId)) {
        _expandedRequestId = null;
      }
      _loading = false;
    });
    widget.onChanged?.call();
  }

  Map<String, int> _computeUnreadByRequest(
    List<AppNotification> unread,
    Map<String, WorkOrder> linked,
  ) {
    final unreadByWorkOrder = <String, int>{};
    for (final n in unread) {
      final workOrderId = (n.data['work_order_id'] ?? '').toString();
      if (workOrderId.isEmpty) continue;
      unreadByWorkOrder[workOrderId] = (unreadByWorkOrder[workOrderId] ?? 0) + 1;
    }

    final unreadByRequest = <String, int>{};
    linked.forEach((requestId, workOrder) {
      final count = unreadByWorkOrder[workOrder.id] ?? 0;
      if (count > 0) unreadByRequest[requestId] = count;
    });
    return unreadByRequest;
  }

  Future<void> _markLinkedWorkOrderNotificationsRead(String workOrderId) async {
    final ids = _unreadNotifications
        .where((n) => (n.data['work_order_id'] ?? '').toString() == workOrderId)
        .map((n) => n.id)
        .toList();
    if (ids.isEmpty) return;

    await Future.wait(ids.map(_notificationService.markRead));
    if (!mounted) return;

    final remaining = _unreadNotifications
        .where((n) => (n.data['work_order_id'] ?? '').toString() != workOrderId)
        .toList();
    setState(() {
      _unreadNotifications = remaining;
      _unreadByRequestId = _computeUnreadByRequest(remaining, _linkedByRequestId);
    });
  }

  List<RequestModel> get _filtered {
    if (_statusFilter == 'All') return _requests;
    return _requests.where((r) => r.status == _statusFilter).toList();
  }

  void _enterSelectionMode(String id) {
    setState(() {
      _selectionMode = true;
      _expandedRequestId = null;
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

  void _toggleExpanded(String requestId) {
    setState(() {
      _expandedRequestId = _expandedRequestId == requestId ? null : requestId;
    });
  }

  Future<void> _deleteSelected() async {
    final count = _selectedIds.length;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.bgSurface,
        title: Text('Delete Requests', style: TextStyle(color: AppColors.textPrimary)),
        content: Text(
          'Delete $count request${count > 1 ? 's' : ''}?',
          style: TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel'),
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
        title: Text('Delete Request', style: TextStyle(color: AppColors.textPrimary)),
        content: Text(
          'Are you sure you want to delete this request?',
          style: TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel'),
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

  Future<void> _openLinkedActivity(WorkOrder workOrder) async {
    await _markLinkedWorkOrderNotificationsRead(workOrder.id);
    if (!mounted) return;
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AddWorkOrderScreen(workOrder: workOrder, initialTab: 1),
      ),
    );
    if (!mounted) return;
    if (result == 'updated' || result == 'deleted') {
      await _load();
    }
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
                          Text(
                            'Requests',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textPrimary,
                              letterSpacing: -0.3,
                            ),
                          ),
                          SizedBox(height: 12),
                          FilterChipRow(
                            filters: const ['All', 'Pending', 'In Progress', 'Closed'],
                            selected: _statusFilter,
                            onSelected: (s) => setState(() => _statusFilter = s),
                          ),
                        ],
                      ),
                    ),
            ),

            Divider(height: 0, thickness: 0.5, color: AppColors.border),

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
                              Icon(
                                Icons.inbox_outlined,
                                size: 48,
                                color: AppColors.bgSurface3,
                              ),
                              SizedBox(height: 12),
                              Text(
                                _statusFilter == 'All'
                                    ? 'No requests yet'
                                    : 'No $_statusFilter requests',
                                style: TextStyle(
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
                            separatorBuilder: (_, __) => SizedBox(height: 8),
                            itemBuilder: (_, i) {
                              final req = _filtered[i];
                              final linkedWorkOrder = _linkedByRequestId[req.id];
                              final expanded = !_selectionMode && _expandedRequestId == req.id;

                              // Selection mode: show checkboxes, no swipe
                              if (_selectionMode) {
                                return _RequestCard(
                                  request: req,
                                  expanded: expanded,
                                  linkedWorkOrder: linkedWorkOrder,
                                  unreadCount: _unreadByRequestId[req.id] ?? 0,
                                  selectionMode: true,
                                  isSelected: _selectedIds.contains(req.id),
                                  onTap: () => _toggleSelection(req.id),
                                );
                              }

                              // Non-requester: no delete, no long press
                              if (!_canDelete) {
                                return _RequestCard(
                                  request: req,
                                  expanded: expanded,
                                  linkedWorkOrder: linkedWorkOrder,
                                  unreadCount: _unreadByRequestId[req.id] ?? 0,
                                  onTap: () => _toggleExpanded(req.id),
                                  onDetails: () => _openDetail(req),
                                  onActivity: linkedWorkOrder != null
                                      ? () => _openLinkedActivity(linkedWorkOrder)
                                      : null,
                                );
                              }

                              // Requester: swipe to reveal delete + long press for multi-select
                              return _SwipeRevealCard(
                                onTap: () => _toggleExpanded(req.id),
                                onLongPress: () => _enterSelectionMode(req.id),
                                onDelete: () => _deleteSingleRequest(req),
                                child: _RequestCard(
                                  request: req,
                                  expanded: expanded,
                                  linkedWorkOrder: linkedWorkOrder,
                                  unreadCount: _unreadByRequestId[req.id] ?? 0,
                                  onDetails: () => _openDetail(req),
                                  onActivity: linkedWorkOrder != null
                                      ? () => _openLinkedActivity(linkedWorkOrder)
                                      : null,
                                ),
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
          icon: Icon(Icons.close_rounded, size: 20, color: AppColors.textPrimary),
          onPressed: onCancel,
          padding: const EdgeInsets.all(8),
        ),
        Expanded(
          child: Text(
            '$count selected',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
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
                      child: Icon(
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
  final VoidCallback? onDetails;
  final VoidCallback? onActivity;
  final WorkOrder? linkedWorkOrder;
  final int unreadCount;
  final bool expanded;
  final bool selectionMode;
  final bool isSelected;

  const _RequestCard({
    required this.request,
    this.onTap,
    this.onDetails,
    this.onActivity,
    this.linkedWorkOrder,
    this.unreadCount = 0,
    this.expanded = false,
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
            color: isSelected
                ? AppColors.accent
                : (expanded ? AppColors.border2 : AppColors.border),
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
                        side: BorderSide(color: AppColors.border2, width: 1.5),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                      ),
                    ),
                  ),
                Expanded(
                  child: Text(
                    request.title,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
                if (unreadCount > 0) ...[
                  SizedBox(width: 6),
                  _UnreadBadge(count: unreadCount),
                ],
                SizedBox(width: 8),
                _StatusBadge(status: request.status),
                if (!selectionMode) ...[
                  SizedBox(width: 6),
                  Icon(
                    expanded
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    size: 18,
                    color: AppColors.textTertiary,
                  ),
                ],
              ],
            ),

            if (request.description.isNotEmpty) ...[
              SizedBox(height: 6),
              Text(
                request.description,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
              ),
            ],

            SizedBox(height: 10),

            Row(
              children: [
                if (request.location.isNotEmpty) ...[
                  Icon(Icons.location_on_outlined,
                      size: 12, color: AppColors.textTertiary),
                  SizedBox(width: 3),
                  Text(
                    request.location,
                    style: TextStyle(
                      fontSize: 11,
                      color: AppColors.textTertiary,
                    ),
                  ),
                  SizedBox(width: 10),
                ],
                Icon(Icons.person_outline_rounded,
                    size: 12, color: AppColors.textTertiary),
                SizedBox(width: 3),
                Text(
                  request.requesterName,
                  style: TextStyle(
                    fontSize: 11,
                    color: AppColors.textTertiary,
                  ),
                ),
                const Spacer(),
                Text(
                  _formatDate(request.createdAt),
                  style: TextStyle(
                    fontSize: 11,
                    color: AppColors.textTertiary,
                  ),
                ),
              ],
            ),

            if (!selectionMode)
              AnimatedCrossFade(
                firstChild: const SizedBox.shrink(),
                secondChild: Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      if (linkedWorkOrder != null && onActivity != null)
                        GestureDetector(
                          onTap: onActivity,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                            decoration: BoxDecoration(
                              color: AppColors.bgSurface2,
                              borderRadius: BorderRadius.circular(9),
                              border: Border.all(color: AppColors.border2, width: 0.5),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.history_rounded, size: 13, color: AppColors.textSecondary),
                                SizedBox(width: 5),
                                Text(
                                  'Activity',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: AppColors.textSecondary,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                if (unreadCount > 0) ...[
                                  SizedBox(width: 6),
                                  _UnreadBadge(count: unreadCount),
                                ],
                              ],
                            ),
                          ),
                        ),
                      if (linkedWorkOrder != null && onActivity != null)
                        SizedBox(width: 8),
                      GestureDetector(
                        onTap: onDetails,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                          decoration: BoxDecoration(
                            color: AppColors.bgSurface2,
                            borderRadius: BorderRadius.circular(9),
                            border: Border.all(color: AppColors.border2, width: 0.5),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.open_in_new_rounded, size: 13, color: AppColors.textSecondary),
                              SizedBox(width: 5),
                              Text(
                                'Details',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: AppColors.textSecondary,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                crossFadeState:
                    expanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
                duration: const Duration(milliseconds: 190),
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
    Color bg;
    Color text;
    if (status == 'Pending') {
      bg = AppColors.pendingBg;
      text = AppColors.pendingText;
    } else if (status == 'In Progress') {
      bg = AppColors.inProgressBg;
      text = AppColors.inProgressText;
    } else {
      bg = AppColors.closedBg;
      text = AppColors.closedText;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        status,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w500,
          color: text,
        ),
      ),
    );
  }
}

class _UnreadBadge extends StatelessWidget {
  final int count;
  const _UnreadBadge({required this.count});

  @override
  Widget build(BuildContext context) {
    final label = count > 99 ? '99+' : '$count';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: AppColors.accent,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w600,
          color: Colors.white,
        ),
      ),
    );
  }
}
