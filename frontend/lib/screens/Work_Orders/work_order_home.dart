import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../models/app_notification.dart';
import '../../models/work_order.dart';
import '../../services/notification_service.dart';
import '../../widgets/claude_widgets.dart';
import '../../widgets/work_order_card.dart';
import '../../services/work_order_service.dart';
import '../../controllers/filter_controller.dart';
import '../../filters/work_order_filter_engine.dart';
import '../../models/employee_assignment.dart';
import '../../theme/app_theme.dart';
import 'add_work_order.dart';

class WorkOrderHome extends StatefulWidget {
  const WorkOrderHome({super.key});

  @override
  State<WorkOrderHome> createState() => _WorkOrderHomeState();
}

class _WorkOrderHomeState extends State<WorkOrderHome>
    with WidgetsBindingObserver {
  final NotificationService _notificationService = NotificationService();
  final FilterController _filter = FilterController();
  final WorkOrderService _service = WorkOrderService();
  final TextEditingController _searchCtrl = TextEditingController();

  List<WorkOrder> _workOrders = [];
  List<AppNotification> _unreadNotifications = [];
  Map<String, int> _unreadByWorkOrderId = {};
  int? _expandedIndex;
  bool _showSearch = false;
  Timer? _notifPollTimer;
  int _lastUnreadTotal = 0;
  bool _soundPrimed = false;
  bool _isForeground = true;

  bool _selectionMode = false;
  final Set<String> _selectedIds = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
    _startNotificationPolling();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _isForeground = state == AppLifecycleState.resumed;
  }

  Future<void> _load() async {
    final data = await _service.fetchWorkOrders();
    await _refreshUnreadNotifications(playSoundIfIncreased: false);
    if (!mounted) return;
    setState(() => _workOrders = data);
  }

  Future<void> _refreshUnreadNotifications({
    bool playSoundIfIncreased = true,
  }) async {
    final unread = await _notificationService.fetchNotifications(
      unreadOnly: true,
      limit: 200,
    );

    final byWorkOrder = <String, int>{};
    for (final n in unread) {
      final woId = (n.data['work_order_id'] ?? '').toString();
      if (woId.isEmpty) continue;
      byWorkOrder[woId] = (byWorkOrder[woId] ?? 0) + 1;
    }

    final total = unread.length;
    if (_soundPrimed && playSoundIfIncreased && _isForeground && total > _lastUnreadTotal) {
      try {
        SystemSound.play(SystemSoundType.alert);
      } catch (_) {}
    }
    _soundPrimed = true;
    _lastUnreadTotal = total;

    if (!mounted) return;
    setState(() {
      _unreadNotifications = unread;
      _unreadByWorkOrderId = byWorkOrder;
    });
  }

  void _startNotificationPolling() {
    _notifPollTimer?.cancel();
    _notifPollTimer = Timer.periodic(const Duration(seconds: 20), (_) {
      _refreshUnreadNotifications();
    });
  }

  Future<void> _markWorkOrderNotificationsRead(String workOrderId) async {
    final ids = _unreadNotifications
        .where((n) => (n.data['work_order_id'] ?? '').toString() == workOrderId)
        .map((n) => n.id)
        .toList();
    if (ids.isEmpty) return;
    await Future.wait(ids.map(_notificationService.markRead));
    await _refreshUnreadNotifications(playSoundIfIncreased: false);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _notifPollTimer?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _enterSelectionMode(String id) {
    setState(() {
      _selectionMode = true;
      _expandedIndex = null;
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
            title: Text('Delete Work Orders',
                style: TextStyle(color: AppColors.textPrimary)),
            content: Text(
              'Delete $count work order${count > 1 ? 's' : ''}?',
              style: TextStyle(color: AppColors.textSecondary),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text('Delete',
                    style: TextStyle(color: Colors.red.shade400)),
              ),
            ],
          ),
        ) ??
        false;

    if (!confirm || !mounted) return;

    final ids = List<String>.from(_selectedIds);
    _exitSelectionMode();
    try {
      await _service.deleteWorkOrders(ids);
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Failed to delete: $e')));
      await _load();
    }
  }

  Future<void> _openAdd() async {
    final now = DateTime.now();
    final jobNo =
        'WO${now.year.toString().substring(2)}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}-${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}${now.second.toString().padLeft(2, '0')}';
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
          builder: (_) => AddWorkOrderScreen(autoGeneratedJobNo: jobNo)),
    );
    if (!mounted) return;
    if (result is WorkOrder) {
      setState(() => _workOrders.insert(0, result));
    }
    if (result == 'updated' || result == 'deleted') await _load();
  }

  @override
  Widget build(BuildContext context) {
    final filtered =
        WorkOrderFilterEngine.applyFilters(_workOrders, _filter);

    return Scaffold(
      backgroundColor: AppColors.bgPrimary,
      body: SafeArea(
        child: Column(
          children: [

            // ── App Bar ───────────────────────────────────────
            Container(
              color: AppColors.bgSurface,
              padding: const EdgeInsets.fromLTRB(8, 6, 8, 10),
              child: _selectionMode
                  ? _SelectionBar(
                      count: _selectedIds.length,
                      onCancel: _exitSelectionMode,
                      onDelete: _selectedIds.isNotEmpty
                          ? _deleteSelected
                          : null,
                    )
                  : Padding(
                      padding: const EdgeInsets.fromLTRB(8, 6, 8, 0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              if (!_showSearch)
                                Expanded(
                                  child: Text(
                                    'Work Orders',
                                    style: TextStyle(
                                        fontSize: 20,
                                        fontWeight: FontWeight.w600,
                                        color: AppColors.textPrimary,
                                        letterSpacing: -0.3),
                                  ),
                                )
                              else
                                Expanded(
                                  child: ClaudeSearchBar(
                                    controller: _searchCtrl,
                                    hintText: 'Search job no, title…',
                                    onChanged: (v) => setState(() =>
                                        _filter.setSearchQuery(
                                            v.toLowerCase())),
                                  ),
                                ),
                              SizedBox(width: 8),
                              ClaudeIconButton(
                                icon: _showSearch
                                    ? Icons.close_rounded
                                    : Icons.search_rounded,
                                onTap: () {
                                  setState(() {
                                    _showSearch = !_showSearch;
                                    if (!_showSearch) {
                                      _searchCtrl.clear();
                                      _filter.setSearchQuery('');
                                    }
                                  });
                                },
                              ),
                              SizedBox(width: 6),
                              ClaudeIconButton(
                                icon: Icons.calendar_today_outlined,
                                onTap: () async {
                                  if (_filter.selectedDate != null) {
                                    setState(() =>
                                        _filter.selectedDate = null);
                                    return;
                                  }
                                  final d = await showDatePicker(
                                    context: context,
                                    initialDate: DateTime.now(),
                                    firstDate: DateTime(2020),
                                    lastDate: DateTime(2100),
                                  );
                                  if (d != null) {
                                    setState(() => _filter.setDate(d));
                                  }
                                },
                              ),
                              SizedBox(width: 6),
                              ClaudeIconButton(
                                icon: Icons.person_outline_rounded,
                                onTap: () async {
                                  if (_filter.selectedEmployeeId != null) {
                                    setState(() =>
                                        _filter.selectedEmployeeId = null);
                                    return;
                                  }
                                  final employees = _workOrders
                                      .expand((wo) => wo.assignedEmployees)
                                      .toList();
                                  final unique = {
                                    for (var e in employees) e.id: e
                                  }.values.toList();
                                  final selected =
                                      await showModalBottomSheet<String>(
                                    context: context,
                                    backgroundColor: AppColors.bgSurface,
                                    shape: const RoundedRectangleBorder(
                                      borderRadius: BorderRadius.vertical(
                                          top: Radius.circular(16)),
                                    ),
                                    builder: (_) =>
                                        _EmployeePicker(employees: unique),
                                  );
                                  if (selected != null) {
                                    setState(
                                        () => _filter.setEmployee(selected));
                                  }
                                },
                              ),
                            ],
                          ),

                          SizedBox(height: 12),

                          // ── Status + Type filter chips ─────────────────
                          FilterChipRow(
                            filters: const [
                              'All',
                              'Pending',
                              'In Progress',
                              'Closed',
                              'Inspection',
                            ],
                            selected: _filter.statusFilter == 'All' &&
                                    _filter.selectedDocumentType ==
                                        'Inspection'
                                ? 'Inspection'
                                : _filter.statusFilter,
                            onSelected: (s) {
                              setState(() {
                                _expandedIndex = null;
                                if (s == 'Inspection') {
                                  // Filter by type instead of status
                                  _filter.setStatus('All');
                                  _filter.setDocumentType('Inspection');
                                } else {
                                  _filter.setStatus(s);
                                  _filter.setDocumentType(null);
                                }
                              });
                            },
                          ),
                        ],
                      ),
                    ),
            ),

            // Active filters row
            if (!_selectionMode &&
                (_filter.selectedDate != null ||
                    _filter.selectedEmployeeId != null))
              Container(
                color: AppColors.bgSurface,
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                child: Row(
                  children: [
                    if (_filter.selectedDate != null)
                      _ActiveFilterChip(
                        label:
                            '${_filter.selectedDate!.day}/${_filter.selectedDate!.month}/${_filter.selectedDate!.year}',
                        onRemove: () =>
                            setState(() => _filter.selectedDate = null),
                      ),
                    if (_filter.selectedEmployeeId != null)
                      _ActiveFilterChip(
                        label: _workOrders
                            .expand((w) => w.assignedEmployees)
                            .firstWhere(
                              (e) => e.id == _filter.selectedEmployeeId,
                              orElse: () =>
                                  EmployeeAssignment(id: '', fullName: ''),
                            )
                            .fullName,
                        onRemove: () => setState(
                            () => _filter.selectedEmployeeId = null),
                      ),
                  ],
                ),
              ),

            Divider(
                height: 0, thickness: 0.5, color: AppColors.border),

            // ── List ──────────────────────────────────────────
            Expanded(
              child: _buildList(filtered),
            ),
          ],
        ),
      ),
      floatingActionButton:
          _selectionMode ? null : ClaudeFAB(onTap: _openAdd),
    );
  }

  Widget _buildList(List<WorkOrder> filtered) {
    // Apply inspection type filter locally
    final items = _filter.selectedDocumentType == 'Inspection'
        ? filtered.where((wo) => wo.type == 'Inspection').toList()
        : filtered;

    if (items.isEmpty) {
      return _EmptyState(
        icon: _filter.selectedDocumentType == 'Inspection'
            ? Icons.checklist_rounded
            : Icons.work_outline_rounded,
        message: _filter.searchQuery.isEmpty
            ? (_filter.selectedDocumentType == 'Inspection'
                ? 'No inspections yet'
                : 'No work orders yet')
            : 'No results found',
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      color: AppColors.accent,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 80),
        itemCount: items.length,
        separatorBuilder: (_, __) => SizedBox(height: 8),
        itemBuilder: (context, i) {
          final wo = items[i];
          return WorkOrderCard(
            workOrder: wo,
            unreadActivityCount: _unreadByWorkOrderId[wo.id] ?? 0,
            expanded: !_selectionMode && _expandedIndex == i,
            selectionMode: _selectionMode,
            isSelected: _selectedIds.contains(wo.id),
            onLongPress: () => _enterSelectionMode(wo.id),
            onTap: () {
              if (_selectionMode) {
                _toggleSelection(wo.id);
              } else {
                setState(() {
                  _expandedIndex = _expandedIndex == i ? null : i;
                });
              }
            },
            onActivity: () async {
              if (_selectionMode) return;
              await _markWorkOrderNotificationsRead(wo.id);
              if (!context.mounted) return;
              final result = await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => AddWorkOrderScreen(
                      workOrder: items[i], initialTab: 1),
                ),
              );
              if (!mounted) return;
              if (result == 'updated' || result == 'deleted') await _load();
              await _refreshUnreadNotifications(playSoundIfIncreased: false);
            },
            onEdit: () async {
              if (_selectionMode) return;
              final result = await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => AddWorkOrderScreen(workOrder: items[i]),
                ),
              );
              if (!mounted) return;
              if (result == 'updated' || result == 'deleted') await _load();
              await _refreshUnreadNotifications(playSoundIfIncreased: false);
            },
          );
        },
      ),
    );
  }
}

// ── Selection bar ─────────────────────────────────────────────────────────────

class _SelectionBar extends StatelessWidget {
  final int count;
  final VoidCallback onCancel;
  final VoidCallback? onDelete;

  const _SelectionBar(
      {required this.count, required this.onCancel, this.onDelete});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        IconButton(
          icon: Icon(Icons.close_rounded,
              size: 20, color: AppColors.textPrimary),
          onPressed: onCancel,
          padding: const EdgeInsets.all(8),
        ),
        Expanded(
          child: Text('$count selected',
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary)),
        ),
        if (onDelete != null)
          IconButton(
            icon: Icon(Icons.delete_outline_rounded,
                size: 22, color: Colors.red.shade400),
            onPressed: onDelete,
            padding: const EdgeInsets.all(8),
          ),
      ],
    );
  }
}

// ── Active filter chip ────────────────────────────────────────────────────────

class _ActiveFilterChip extends StatelessWidget {
  final String label;
  final VoidCallback onRemove;

  const _ActiveFilterChip({required this.label, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(right: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.accentBg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
            color: AppColors.accent.withValues(alpha: 0.2), width: 0.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label,
              style: TextStyle(
                  fontSize: 11,
                  color: AppColors.accent,
                  fontWeight: FontWeight.w500)),
          SizedBox(width: 4),
          GestureDetector(
            onTap: onRemove,
            child: Icon(Icons.close_rounded,
                size: 12, color: AppColors.accent),
          ),
        ],
      ),
    );
  }
}

// ── Employee picker ───────────────────────────────────────────────────────────

class _EmployeePicker extends StatelessWidget {
  final List<EmployeeAssignment> employees;
  const _EmployeePicker({required this.employees});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Filter by employee',
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary)),
          SizedBox(height: 12),
          ...employees.map((emp) => ListTile(
                contentPadding: EdgeInsets.zero,
                leading:
                    InitialsAvatar(name: emp.fullName, size: 34, large: false),
                title: Text(emp.fullName,
                    style: TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w500)),
                onTap: () => Navigator.pop(context, emp.id),
              )),
        ],
      ),
    );
  }
}

// ── Empty state ───────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String message;
  const _EmptyState({required this.icon, required this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 48, color: AppColors.bgSurface3),
          SizedBox(height: 12),
          Text(message,
              style: TextStyle(
                  fontSize: 14,
                  color: AppColors.textTertiary,
                  fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}
