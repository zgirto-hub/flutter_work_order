import 'dart:async';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/app_notification.dart';
import '../../models/work_order.dart';
import '../../services/notification_service.dart';
import '../../widgets/claude_widgets.dart';
import '../../widgets/work_order_card.dart';
import '../../services/work_order_service.dart';
import '../../services/signature_service.dart';
import '../../services/report_service.dart';
import '../../widgets/pdf_preview_screen.dart';
import '../../controllers/filter_controller.dart';
import '../../filters/work_order_filter_engine.dart';
import '../../models/technician_assignment.dart';
import '../../theme/app_theme.dart';
import 'add_work_order.dart';

class WorkOrderHome extends StatefulWidget {
  final String userRole;
  final VoidCallback? onWorkOrderCreated;

  const WorkOrderHome({
    super.key,
    this.userRole = 'admin',
    this.onWorkOrderCreated,
  });

  @override
  State<WorkOrderHome> createState() => _WorkOrderHomeState();
}

class NewWorkOrderIntent extends Intent {
  const NewWorkOrderIntent();
}

class SearchIntent extends Intent {
  const SearchIntent();
}

class ClearFiltersIntent extends Intent {
  const ClearFiltersIntent();
}

class _WorkOrderHomeState extends State<WorkOrderHome>
    with WidgetsBindingObserver {
  final NotificationService _notificationService = NotificationService();
  final FilterController _filter = FilterController();
  final WorkOrderService _service = WorkOrderService();
  final TextEditingController _searchCtrl = TextEditingController();

  final ScrollController _scrollController = ScrollController();
  List<WorkOrder> _workOrders = [];
  List<AppNotification> _unreadNotifications = [];
  Map<String, int> _unreadByWorkOrderId = {};
  int? _expandedIndex;
  bool _showSearch = false;
  bool _loadingMore = false;
  bool _hasMore = true;
  int _total = 0;
  static const _pageSize = 30;
  Timer? _notifPollTimer;
  int _lastUnreadTotal = 0;
  bool _soundPrimed = false;
  bool _isForeground = true;

  bool _selectionMode = false;
  final Set<String> _selectedIds = {};
  bool _navigatingToActivity = false;
  bool _navigatingToEdit = false;
  Set<String> _newWoIds = {};
  Set<String> _removingWoIds = {};
  bool _refreshing = false;
  String _userRole = 'admin';
  int _approvalLevel = 0;
  List<String> _userDepartmentIds = [];
  final SignatureService _signatureService = SignatureService();
  Map<String, String> _signatureStates = {};

  bool _profileLoaded = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scrollController.addListener(_onScroll);
    _loadProfile();
    _startNotificationPolling();
  }

  Future<void> _loadProfile() async {
    try {
      final profile = await _service.getEmployeeProfile();
      if (profile != null && mounted) {
        setState(() {
          _userRole = (profile['user_type'] ?? widget.userRole).toString();
          _approvalLevel = profile['approval_level'] as int? ?? 0;
          _userDepartmentIds = (profile['department_ids'] as List<dynamic>?)
                  ?.map((e) => e.toString())
                  .toList() ??
              [];
          _profileLoaded = true;
        });
        await _load();
      }
    } catch (_) {
      if (mounted) {
        setState(() => _profileLoaded = true);
        await _load();
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _isForeground = state == AppLifecycleState.resumed;
    // Refresh data when app comes back to foreground
    if (state == AppLifecycleState.resumed && _profileLoaded && !_loadingMore) {
      _load();
    }
  }

  Future<void> _load() async {
    if (!_profileLoaded) return;
    final result = await _service.fetchWorkOrders(
      userRole: _userRole,
      limit: _pageSize,
      offset: 0,
    );
    if (!mounted) return;
    _refreshUnreadNotifications(playSoundIfIncreased: false);
    final oldIds = _workOrders.map((wo) => wo.id).toSet();
    final newIds = result.items.map((wo) => wo.id).toSet();
    setState(() {
      _newWoIds = oldIds.isEmpty ? {} : newIds.difference(oldIds);
      _workOrders = result.items;
      _total = result.total;
      _hasMore = result.items.length >= _pageSize;
    });
    if (_newWoIds.isNotEmpty) {
      Future.delayed(const Duration(milliseconds: 800), () {
        if (mounted) setState(() => _newWoIds = {});
      });
    }
    _refreshSignatureStatus(result.items);
  }

  Future<void> _refreshSignatureStatus(List<WorkOrder> workOrders) async {
    final closedIds = workOrders
        .where((wo) => wo.status == 'Closed')
        .map((wo) => wo.id)
        .toList();
    if (closedIds.isEmpty) {
      if (_signatureStates.isNotEmpty && mounted) {
        setState(() => _signatureStates = {});
      }
      return;
    }

    try {
      final statuses =
          await _signatureService.fetchBulkSignatureStatus(closedIds);
      if (!mounted) return;

      final newStates = <String, String>{};
      for (final wo in workOrders.where((wo) => wo.status == 'Closed')) {
        final status = statuses[wo.id];
        if (status == null) {
          newStates[wo.id] = 'unsigned';
        } else {
          final sigStatus = status['signature_status'] as String? ?? 'unsigned';
          final techStatus = status['technician_status'] as String?;
          final supStatus = status['supervisor_status'] as String?;
          final superStatus = status['superintendent_status'] as String?;

          if (sigStatus == 'unsigned' || sigStatus == 'rejected') {
            newStates[wo.id] = 'unsigned';
          } else if (sigStatus == 'completed') {
            newStates[wo.id] = 'fully_signed';
          } else if (sigStatus == 'tech_signed') {
            newStates[wo.id] = 'pending_supervisor';
          } else if (sigStatus == 'supervisor_approved') {
            newStates[wo.id] = 'pending_superintendent';
          } else if (techStatus == 'approved' &&
              supStatus == 'approved' &&
              superStatus == 'approved') {
            newStates[wo.id] = 'fully_signed';
          } else {
            newStates[wo.id] = 'pending';
          }
        }
      }
      if (mounted) setState(() => _signatureStates = newStates);
    } catch (_) {}
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore || !_profileLoaded) return;
    setState(() => _loadingMore = true);
    try {
      final result = await _service.fetchWorkOrders(
        userRole: _userRole,
        limit: _pageSize,
        offset: _workOrders.length,
      );
      if (mounted) {
        setState(() {
          _workOrders.addAll(result.items);
          _total = result.total;
          _hasMore = result.items.length >= _pageSize;
        });
      }
    } catch (_) {}
    if (mounted) setState(() => _loadingMore = false);
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
    if (_soundPrimed &&
        playSoundIfIncreased &&
        _isForeground &&
        total > _lastUnreadTotal) {
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

  void _onScroll() {
    if (_loadingMore || !_hasMore) return;
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 300) {
      _loadMore();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _notifPollTimer?.cancel();
    _scrollController.dispose();
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

  String? _getNextStatus(String currentStatus) {
    switch (currentStatus.toLowerCase()) {
      case 'pending':
        return 'In Progress';
      case 'in progress':
        return 'Resolved';
      case 'resolved':
        return 'Closed';
      case 'closed':
        return null;
      default:
        return null;
    }
  }

  Future<void> _showQuickStatusSheet(WorkOrder wo) async {
    final nextStatus = _getNextStatus(wo.status);
    if (nextStatus == null) return;

    final isCloseFlow = wo.status.toLowerCase() == 'resolved';
    final techNotesController = TextEditingController();
    var isLoading = false;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            Future<void> submitStatusUpdate() async {
              if (isLoading) return;

              setSheetState(() => isLoading = true);

              try {
                if (isCloseFlow) {
                  final closedBy =
                      Supabase.instance.client.auth.currentUser?.id;
                  if (closedBy == null || closedBy.isEmpty) {
                    throw Exception('Unable to determine the current user.');
                  }

                  final techNotes = techNotesController.text.trim();
                  await _service.closeWorkOrder(
                    wo.id,
                    closedBy: closedBy,
                    techNotes: techNotes.isEmpty ? null : techNotes,
                  );

                  final index =
                      _workOrders.indexWhere((item) => item.id == wo.id);
                  if (index != -1) {
                    _workOrders[index] = _workOrders[index].copyWith(
                      status: 'Closed',
                      closedBy: closedBy,
                      closedAt: DateTime.now().toIso8601String(),
                      techNotes: techNotes.isEmpty ? null : techNotes,
                    );
                  }
                } else {
                  final updatedWo = wo.copyWith(status: nextStatus);
                  await _service.updateWorkOrder(updatedWo);

                  final index =
                      _workOrders.indexWhere((item) => item.id == wo.id);
                  if (index != -1) {
                    _workOrders[index] = updatedWo;
                  }
                }

                if (!mounted) return;
                setState(() {});
                Navigator.of(this.context).pop();
              } catch (e) {
                if (!mounted) return;
                ScaffoldMessenger.of(this.context).showSnackBar(
                  SnackBar(
                    content: Text('Failed to update status: $e'),
                    backgroundColor: AppColors.dangerText,
                    behavior: SnackBarBehavior.floating,
                  ),
                );
                setSheetState(() => isLoading = false);
              }
            }

            return Padding(
              padding: EdgeInsets.fromLTRB(
                16,
                16,
                16,
                16 + MediaQuery.of(sheetContext).viewInsets.bottom,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: AppColors.border2,
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  StatusBadge(status: wo.status),
                  const SizedBox(height: 12),
                  Text(
                    wo.title,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    wo.jobNo,
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.textTertiary,
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (isCloseFlow) ...[
                    TextField(
                      controller: techNotesController,
                      enabled: !isLoading,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        labelText: 'Tech Notes (optional)',
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: isLoading ? null : submitStatusUpdate,
                      child: isLoading
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : Text(
                              isCloseFlow
                                  ? 'Close Work Order'
                                  : 'Mark as $nextStatus',
                            ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );

    techNotesController.dispose();
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
      setState(() => _removingWoIds = ids.toSet());
      await Future.delayed(const Duration(milliseconds: 550));
      setState(() {
        _removingWoIds = {};
        _workOrders.removeWhere((wo) => ids.contains(wo.id));
      });
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
      widget.onWorkOrderCreated?.call();
    }
    if (result == 'updated' || result == 'deleted') {
      await _load();
      widget.onWorkOrderCreated?.call();
    }
  }

  void _toggleSearch() {
    setState(() {
      _showSearch = !_showSearch;
      if (!_showSearch) {
        _searchCtrl.clear();
        _filter.setSearchQuery('');
      }
    });
  }

  void _clearFilters() {
    setState(() {
      _filter.setSearchQuery('');
      _filter.setDate(null);
      _filter.setEmployee(null);
      _showSearch = false;
      _searchCtrl.clear();
    });
  }

  Future<void> _toggleDateFilter() async {
    if (_filter.selectedDate != null) {
      setState(() => _filter.selectedDate = null);
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
  }

  Future<void> _showEmployeeFilter() async {
    if (_filter.selectedEmployeeId != null) {
      setState(() => _filter.selectedEmployeeId = null);
      return;
    }
    final employees = _workOrders
        .where((wo) => wo.assignedTechnician != null)
        .map((wo) => wo.assignedTechnician!)
        .toList();
    final unique = {for (var e in employees) e.id: e}.values.toList();
    final selected = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppColors.bgSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => _EmployeePicker(employees: unique),
    );
    if (selected != null) {
      setState(() => _filter.setEmployee(selected));
    }
  }

  @override
  Widget build(BuildContext context) {
    final filtered = WorkOrderFilterEngine.applyFilters(_workOrders, _filter);

    return Shortcuts(
      shortcuts: <LogicalKeySet, Intent>{
        LogicalKeySet(LogicalKeyboardKey.keyN, LogicalKeyboardKey.control):
            const NewWorkOrderIntent(),
        LogicalKeySet(LogicalKeyboardKey.keyF, LogicalKeyboardKey.control):
            const SearchIntent(),
        LogicalKeySet(LogicalKeyboardKey.escape): const ClearFiltersIntent(),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          NewWorkOrderIntent: CallbackAction<NewWorkOrderIntent>(
            onInvoke: (_) => _openAdd(),
          ),
          SearchIntent: CallbackAction<SearchIntent>(
            onInvoke: (_) => _toggleSearch(),
          ),
          ClearFiltersIntent: CallbackAction<ClearFiltersIntent>(
            onInvoke: (_) => _clearFilters(),
          ),
        },
        child: Focus(
          autofocus: true,
          child: Scaffold(
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
                                        child: Semantics(
                                          header: true,
                                          child: Text(
                                            'Work Orders',
                                            style: TextStyle(
                                                fontSize: 20,
                                                fontWeight: FontWeight.w600,
                                                color: AppColors.textPrimary,
                                                letterSpacing: -0.3),
                                          ),
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
                                      onTap: _toggleSearch,
                                      tooltip: _showSearch
                                          ? 'Close search'
                                          : 'Search',
                                      semanticsLabel: _showSearch
                                          ? 'Close search'
                                          : 'Search work orders',
                                    ),
                                    SizedBox(width: 6),
                                    ClaudeIconButton(
                                      icon: Icons.calendar_today_outlined,
                                      onTap: _toggleDateFilter,
                                      tooltip: 'Filter by date',
                                      semanticsLabel: 'Filter by date',
                                    ),
                                    SizedBox(width: 6),
                                    ClaudeIconButton(
                                      icon: Icons.person_outline_rounded,
                                      onTap: _showEmployeeFilter,
                                      tooltip: 'Filter by employee',
                                      semanticsLabel: 'Filter by employee',
                                    ),
                                    SizedBox(width: 6),
                                    if (_refreshing)
                                      Container(
                                        width: 34,
                                        height: 34,
                                        decoration: BoxDecoration(
                                          color: AppColors.bgSurface2,
                                          borderRadius:
                                              BorderRadius.circular(9),
                                          border: Border.all(
                                              color: AppColors.border2,
                                              width: 0.5),
                                        ),
                                        child: Center(
                                          child: SizedBox(
                                            width: 14,
                                            height: 14,
                                            child: CircularProgressIndicator(
                                                strokeWidth: 1.5,
                                                color: AppColors.textTertiary),
                                          ),
                                        ),
                                      )
                                    else
                                      ClaudeIconButton(
                                        icon: Icons.refresh_rounded,
                                        onTap: () async {
                                          setState(() => _refreshing = true);
                                          await _load();
                                          if (mounted) {
                                            setState(() => _refreshing = false);
                                          }
                                        },
                                        tooltip: 'Refresh',
                                        semanticsLabel: 'Refresh work orders',
                                      ),
                                  ],
                                ),

                                SizedBox(height: 12),

                                // ── Status + Type filter chips ─────────────────
                                FilterChipRow(
                                  filters: [
                                    'All',
                                    'Pending',
                                    'In Progress',
                                    'Closed',
                                    if (_userRole != 'reporter') 'Inspection',
                                  ],
                                  selected: _filter.statusFilter == 'All' &&
                                          _filter.selectedFileType ==
                                              'Inspection'
                                      ? 'Inspection'
                                      : _filter.statusFilter,
                                  onSelected: (s) {
                                    setState(() {
                                      _expandedIndex = null;
                                      if (s == 'Inspection') {
                                        _filter.setStatus('All');
                                        _filter.setFileType('Inspection');
                                      } else {
                                        _filter.setStatus(s);
                                        _filter.setFileType(null);
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
                                  .where((w) => w.assignedTechnician != null)
                                  .map((w) => w.assignedTechnician!)
                                  .firstWhere(
                                    (e) => e.id == _filter.selectedEmployeeId,
                                    orElse: () => TechnicianAssignment(
                                        id: '', fullName: ''),
                                  )
                                  .fullName,
                              onRemove: () => setState(
                                  () => _filter.selectedEmployeeId = null),
                            ),
                        ],
                      ),
                    ),

                  Divider(height: 0, thickness: 0.5, color: AppColors.border),

                  // ── List ──────────────────────────────────────────
                  Expanded(
                    child: _buildList(filtered),
                  ),
                ],
              ),
            ),
            floatingActionButton: _selectionMode
                ? null
                : ClaudeFAB(
                    onTap: _openAdd,
                    tooltip: 'Create work order',
                    semanticsLabel: 'Create new work order',
                  ),
          ),
        ),
      ),
    );
  }

  String _dateLabel(String dateStr) {
    final dt = DateTime.tryParse(dateStr);
    if (dt == null) return '';
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final entryDay = DateTime(dt.year, dt.month, dt.day);
    if (entryDay == today) return 'Today';
    if (entryDay == yesterday) return 'Yesterday';
    return '${dt.day}/${dt.month}/${dt.year}';
  }

  Widget _buildList(List<WorkOrder> filtered) {
    // Apply inspection type filter locally
    final items = _filter.selectedFileType == 'Inspection'
        ? filtered.where((wo) => wo.type == 'Inspection').toList()
        : filtered;

    if (items.isEmpty) {
      return RefreshIndicator(
        onRefresh: _load,
        color: AppColors.accent,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            SizedBox(
              height: MediaQuery.of(context).size.height * 0.5,
              child: _EmptyState(
                icon: _filter.selectedFileType == 'Inspection'
                    ? Icons.checklist_rounded
                    : Icons.work_outline_rounded,
                message: _filter.searchQuery.isEmpty
                    ? (_filter.selectedFileType == 'Inspection'
                        ? 'No inspections yet'
                        : 'No work orders yet')
                    : 'No results found',
              ),
            ),
          ],
        ),
      );
    }

    // Group by date
    final grouped =
        groupBy<WorkOrder, String>(items, (wo) => _dateLabel(wo.dateCreated));

    // Build flat list of widgets with date headers
    final widgets = <Widget>[];
    for (final entry in grouped.entries) {
      // Date divider
      widgets.add(Padding(
        padding: const EdgeInsets.only(bottom: 8, top: 4),
        child: Row(
          children: [
            Expanded(
                child: Divider(
                    height: 1, thickness: 0.5, color: AppColors.border2)),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.bgSurface2,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.border2, width: 0.5),
                ),
                child: Text(entry.key,
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textSecondary)),
              ),
            ),
            Expanded(
                child: Divider(
                    height: 1, thickness: 0.5, color: AppColors.border2)),
          ],
        ),
      ));
      // WO cards for this date
      for (final wo in entry.value) {
        final i = items.indexOf(wo);
        final isNew = _newWoIds.contains(wo.id);
        final isRemoving = _removingWoIds.contains(wo.id);
        widgets.add(TweenAnimationBuilder<double>(
            key: ValueKey('anim_${wo.id}_${isRemoving ? 'out' : 'in'}'),
            tween: isRemoving
                ? Tween(begin: 1.0, end: 0.0)
                : Tween(begin: isNew ? 0.0 : 1.0, end: 1.0),
            duration:
                Duration(milliseconds: isRemoving ? 500 : (isNew ? 600 : 0)),
            curve: isRemoving ? Curves.easeInCubic : Curves.easeOutCubic,
            builder: (context, value, child) => Opacity(
                  opacity: value.clamp(0.0, 1.0),
                  child: Transform.translate(
                    offset: Offset(isRemoving ? -20 * (1 - value) : 0,
                        isRemoving ? 0 : 12 * (1 - value)),
                    child: child,
                  ),
                ),
            child: Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: WorkOrderCard(
                workOrder: wo,
                unreadActivityCount: _unreadByWorkOrderId[wo.id] ?? 0,
                expanded: !_selectionMode && _expandedIndex == i,
                selectionMode: _selectionMode,
                onStatusTap: (_userRole != 'reporter' &&
                        _getNextStatus(wo.status) != null)
                    ? () => _showQuickStatusSheet(wo)
                    : null,
                isSelected: _selectedIds.contains(wo.id),
                signatureState: _signatureStates[wo.id],
                approvalLevel: _approvalLevel,
                userDepartmentIds: _userDepartmentIds,
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
                  if (_navigatingToActivity) return;
                  _navigatingToActivity = true;
                  try {
                    await _markWorkOrderNotificationsRead(wo.id);
                    if (!mounted) return;
                    final result = await Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) =>
                            AddWorkOrderScreen(workOrder: wo, initialTab: 1),
                      ),
                    );
                    if (!mounted) return;
                    if (result == 'updated' || result == 'deleted') {
                      await _load();
                      widget.onWorkOrderCreated?.call();
                    }
                    await _refreshUnreadNotifications(
                        playSoundIfIncreased: false);
                  } finally {
                    _navigatingToActivity = false;
                  }
                },
                onEdit: () async {
                  if (_selectionMode) return;
                  if (_navigatingToEdit) return;
                  _navigatingToEdit = true;
                  try {
                    final result = await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => AddWorkOrderScreen(workOrder: wo),
                      ),
                    );
                    if (!mounted) return;
                    if (result == 'updated' || result == 'deleted') {
                      await _load();
                      widget.onWorkOrderCreated?.call();
                    }
                    await _refreshUnreadNotifications(
                        playSoundIfIncreased: false);
                  } finally {
                    _navigatingToEdit = false;
                  }
                },
                onExportPdf: wo.status.toLowerCase() == 'closed'
                    ? () async {
                        final currentUser =
                            Supabase.instance.client.auth.currentUser;
                        final email = currentUser?.email ?? '';
                        try {
                          await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => PdfPreviewScreen(
                                title: 'WO-${wo.jobNo ?? "unknown"} Report',
                                buildPdf: () =>
                                    ReportService().exportWorkOrderPdf(
                                  workOrderId: wo.id,
                                  email: email,
                                  userRole: _userRole ?? 'reporter',
                                ),
                              ),
                            ),
                          );
                        } catch (e) {
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                  content: Text('Failed to export PDF: $e')),
                            );
                          }
                        }
                      }
                    : null,
              ),
            )));
      }
    }

    // Loading more indicator
    if (_loadingMore) {
      widgets.add(Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
                strokeWidth: 2, color: AppColors.accent),
          ),
        ),
      ));
    }
    if (!_hasMore && _workOrders.length > _pageSize) {
      widgets.add(Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Center(
          child: Text('All $_total work orders loaded',
              style: TextStyle(fontSize: 11, color: AppColors.textTertiary)),
        ),
      ));
    }

    return RefreshIndicator(
      onRefresh: _load,
      color: AppColors.accent,
      child: ListView(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 80),
        children: widgets,
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
          icon:
              Icon(Icons.close_rounded, size: 20, color: AppColors.textPrimary),
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
            child: Icon(Icons.close_rounded, size: 12, color: AppColors.accent),
          ),
        ],
      ),
    );
  }
}

// ── Employee picker ───────────────────────────────────────────────────────────

class _EmployeePicker extends StatelessWidget {
  final List<TechnicianAssignment> employees;
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
                    style:
                        TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
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
