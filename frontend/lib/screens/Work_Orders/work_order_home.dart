import 'package:flutter/material.dart';
import '../../models/work_order.dart';
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

class _WorkOrderHomeState extends State<WorkOrderHome> {
  final FilterController _filter = FilterController();
  final WorkOrderService _service = WorkOrderService();
  final TextEditingController _searchCtrl = TextEditingController();

  List<WorkOrder> _workOrders = [];
  int? _expandedIndex;
  bool _showSearch = false;

  // Selection mode
  bool _selectionMode = false;
  final Set<String> _selectedIds = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final data = await _service.fetchWorkOrders();
    if (!mounted) return;
    setState(() => _workOrders = data);
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
        title: const Text('Delete Work Orders', style: TextStyle(color: AppColors.textPrimary)),
        content: Text(
          'Delete $count work order${count > 1 ? 's' : ''}?',
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
    try {
      await _service.deleteWorkOrders(ids);
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to delete: $e')),
      );
      await _load();
    }
  }

  Future<void> _openAdd() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => AddWorkOrderScreen()),
    );
    if (!mounted) return;
    if (result is WorkOrder) {
      setState(() => _workOrders.insert(0, result));
    }
    if (result == 'updated' || result == 'deleted') await _load();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = WorkOrderFilterEngine.applyFilters(_workOrders, _filter);

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
                      onDelete: _selectedIds.isNotEmpty ? _deleteSelected : null,
                    )
                  : Padding(
                      padding: const EdgeInsets.fromLTRB(8, 6, 8, 0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              if (!_showSearch)
                                const Expanded(
                                  child: Text(
                                    'Work Orders',
                                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: AppColors.textPrimary, letterSpacing: -0.3),
                                  ),
                                )
                              else
                                Expanded(
                                  child: ClaudeSearchBar(
                                    controller: _searchCtrl,
                                    hintText: 'Search job no, title…',
                                    onChanged: (v) {
                                      setState(() => _filter.setSearchQuery(v.toLowerCase()));
                                    },
                                  ),
                                ),
                              const SizedBox(width: 8),
                              ClaudeIconButton(
                                icon: _showSearch ? Icons.close_rounded : Icons.search_rounded,
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
                              const SizedBox(width: 6),
                              ClaudeIconButton(
                                icon: Icons.calendar_today_outlined,
                                onTap: () async {
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
                                  if (d != null) setState(() => _filter.setDate(d));
                                },
                              ),
                              const SizedBox(width: 6),
                              ClaudeIconButton(
                                icon: Icons.person_outline_rounded,
                                onTap: () async {
                                  if (_filter.selectedEmployeeId != null) {
                                    setState(() => _filter.selectedEmployeeId = null);
                                    return;
                                  }
                                  final employees = _workOrders
                                      .expand((wo) => wo.assignedEmployees)
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
                                  if (selected != null) setState(() => _filter.setEmployee(selected));
                                },
                              ),
                            ],
                          ),

                          const SizedBox(height: 12),

                          // Status filter chips
                          FilterChipRow(
                            filters: const ['All', 'Pending', 'In Progress', 'Closed'],
                            selected: _filter.statusFilter,
                            onSelected: (s) => setState(() {
                              _filter.setStatus(s);
                              _expandedIndex = null;
                            }),
                          ),
                        ],
                      ),
                    ),
            ),

            // Active filters row
            if (!_selectionMode && (_filter.selectedDate != null || _filter.selectedEmployeeId != null))
              Container(
                color: AppColors.bgSurface,
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                child: Row(
                  children: [
                    if (_filter.selectedDate != null)
                      _ActiveFilterChip(
                        label: '${_filter.selectedDate!.day}/${_filter.selectedDate!.month}/${_filter.selectedDate!.year}',
                        onRemove: () => setState(() => _filter.selectedDate = null),
                      ),
                    if (_filter.selectedEmployeeId != null)
                      _ActiveFilterChip(
                        label: _workOrders
                            .expand((w) => w.assignedEmployees)
                            .firstWhere((e) => e.id == _filter.selectedEmployeeId,
                                orElse: () => EmployeeAssignment(id: '', fullName: ''))
                            .fullName,
                        onRemove: () => setState(() => _filter.selectedEmployeeId = null),
                      ),
                  ],
                ),
              ),

            // Thin border
            const Divider(height: 0, thickness: 0.5, color: AppColors.border),

            // ── List ──────────────────────────────────────────
            Expanded(
              child: filtered.isEmpty
                  ? _EmptyState(
                      icon: Icons.work_outline_rounded,
                      message: _filter.searchQuery.isEmpty ? 'No work orders yet' : 'No results found',
                    )
                  : RefreshIndicator(
                      onRefresh: _load,
                      color: AppColors.accent,
                      child: ListView.separated(
                        padding: const EdgeInsets.fromLTRB(14, 12, 14, 80),
                        itemCount: filtered.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (context, i) {
                          final wo = filtered[i];
                          return WorkOrderCard(
                            workOrder: wo,
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
                            onEdit: () async {
                              if (_selectionMode) return;
                              final result = await Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => AddWorkOrderScreen(workOrder: filtered[i]),
                                ),
                              );
                              if (!mounted) return;
                              if (result == 'updated' || result == 'deleted') await _load();
                            },
                          );
                        },
                      ),
                    ),
            ),
          ],
        ),
      ),
      floatingActionButton: _selectionMode ? null : ClaudeFAB(onTap: _openAdd),
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
        border: Border.all(color: AppColors.accent.withValues(alpha: 0.2), width: 0.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: const TextStyle(fontSize: 11, color: AppColors.accent, fontWeight: FontWeight.w500)),
          const SizedBox(width: 4),
          GestureDetector(
            onTap: onRemove,
            child: const Icon(Icons.close_rounded, size: 12, color: AppColors.accent),
          ),
        ],
      ),
    );
  }
}

// ── Employee picker bottom sheet ──────────────────────────────────────────────

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
          const Text('Filter by employee', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
          const SizedBox(height: 12),
          ...employees.map((emp) => ListTile(
                contentPadding: EdgeInsets.zero,
                leading: InitialsAvatar(name: emp.fullName, size: 34, large: false),
                title: Text(emp.fullName, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
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
          const SizedBox(height: 12),
          Text(message, style: const TextStyle(fontSize: 14, color: AppColors.textTertiary, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}
