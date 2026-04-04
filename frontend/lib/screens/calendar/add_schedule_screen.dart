import 'package:flutter/material.dart';
import '../../models/recurring_inspection.dart';
import '../../models/department.dart';
import '../../models/user.dart';
import '../../models/work_order.dart';
import '../../models/technician_assignment.dart';
import '../../services/schedule_service.dart';
import '../../services/department_service.dart';
import '../../services/user_service.dart';
import '../../services/work_order_service.dart';
import '../../widgets/technician_selector.dart';
import '../../theme/app_theme.dart';

enum _RepeatOption {
  never,
  everyDay,
  everyWeek,
  every2Weeks,
  everyMonth,
  everyYear,
  custom
}

enum _Tab { workOrder, inspection }

class AddScheduleScreen extends StatefulWidget {
  final String userRole;
  final RecurringInspection? existing;

  const AddScheduleScreen({
    super.key,
    required this.userRole,
    this.existing,
  });

  @override
  State<AddScheduleScreen> createState() => _AddScheduleScreenState();
}

class _AddScheduleScreenState extends State<AddScheduleScreen> {
  final _service = ScheduleService();
  final _departmentService = DepartmentService();
  final _userService = UserService();
  final _woService = WorkOrderService();

  // Tab (only used when creating new)
  _Tab _tab = _Tab.workOrder;

  // Shared data
  List<Department> _departments = [];
  List<AppUser> _technicians = [];
  bool _loadingData = true;
  bool _saving = false;
  bool _deleting = false;

  bool get _isEditing => widget.existing != null;

  // ── Inspection state ─────────────────────────────────────────────────────────
  final _titleCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _locationCtrl = TextEditingController();
  String _selectedDeptId = '';
  String _inspectionType = 'Inspection';
  List<String> _selectedTechIds = [];
  DateTime _date = DateTime.now();
  DateTime? _endDate;
  _RepeatOption _repeat = _RepeatOption.never;
  String _customFrequency = 'daily';
  int _customInterval = 1;
  bool _isActive = true;

  // ── Work Order state ─────────────────────────────────────────────────────────
  final _woTitleCtrl = TextEditingController();
  final _woDescCtrl = TextEditingController();
  final _woLocationCtrl = TextEditingController();
  String _woDeptId = '';
  List<String> _woTechIds = [];
  String _woType = 'Technical';
  DateTime _woDate = DateTime.now();
  DateTime? _woEndDate;
  _RepeatOption _woRepeat = _RepeatOption.never;
  String _woCustomFrequency = 'daily';
  int _woCustomInterval = 1;

  // Display controllers for date fields (TextFormField needs controller to update on setState)
  final _dateCtrl = TextEditingController();
  final _woDateCtrl = TextEditingController();
  final _endDateCtrl = TextEditingController();
  final _woEndDateCtrl = TextEditingController();

  static const _woTypes = ['Technical', 'Inspection', 'Other'];

  // ── Init ─────────────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    if (widget.userRole == 'technician') _tab = _Tab.inspection;
    if (_isEditing) {
      _tab = _Tab.inspection;
      final e = widget.existing!;
      _titleCtrl.text = e.title;
      _descCtrl.text = e.description;
      _locationCtrl.text = e.location;
      _selectedDeptId = e.departmentId;
      _inspectionType = e.type;
      _isActive = e.isActive;
      _selectedTechIds = e.assignees.map((a) => a.id).toList();
      _date = DateTime.tryParse(e.startDate) ?? DateTime.now();
      _endDate = (e.endDate != null && e.endDate != e.startDate)
          ? DateTime.tryParse(e.endDate!)
          : null;

      if (e.endDate == e.startDate) {
        _repeat = _RepeatOption.never;
      } else if (e.frequency == 'daily' && (e.interval ?? 1) == 1) {
        _repeat = _RepeatOption.everyDay;
      } else if (e.frequency == 'weekly' && (e.interval ?? 1) == 1) {
        _repeat = _RepeatOption.everyWeek;
      } else if (e.frequency == 'weekly' && (e.interval ?? 1) == 2) {
        _repeat = _RepeatOption.every2Weeks;
      } else if (e.frequency == 'monthly' && (e.interval ?? 1) == 1) {
        _repeat = _RepeatOption.everyMonth;
      } else if (e.frequency == 'yearly' && (e.interval ?? 1) == 1) {
        _repeat = _RepeatOption.everyYear;
      } else {
        _repeat = _RepeatOption.custom;
        _customFrequency = e.frequency;
        _customInterval = e.interval ?? 1;
      }
    }
    _dateCtrl.text = _displayDate(_date);
    _woDateCtrl.text = _displayDate(_woDate);
    _loadFormData();
  }

  Future<void> _loadFormData() async {
    try {
      final depts = await _departmentService.fetchDepartments(isActive: true);
      final techs = await _userService.fetchUsers();
      if (!mounted) return;
      setState(() {
        _departments = depts;
        _technicians =
            techs.where((u) => u.userType == UserType.technician).toList();
        if (_selectedDeptId.isEmpty && depts.isNotEmpty)
          _selectedDeptId = depts.first.id;
        if (_woDeptId.isEmpty && depts.isNotEmpty) _woDeptId = depts.first.id;
        _loadingData = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingData = false);
    }
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    _locationCtrl.dispose();
    _woTitleCtrl.dispose();
    _woDescCtrl.dispose();
    _woLocationCtrl.dispose();
    _dateCtrl.dispose();
    _woDateCtrl.dispose();
    _endDateCtrl.dispose();
    _woEndDateCtrl.dispose();
    super.dispose();
  }

  // ── Derived params (work order repeat) ───────────────────────────────────────

  String get _woFrequency {
    switch (_woRepeat) {
      case _RepeatOption.never:
      case _RepeatOption.everyDay:
        return 'daily';
      case _RepeatOption.everyWeek:
      case _RepeatOption.every2Weeks:
        return 'weekly';
      case _RepeatOption.everyMonth:
        return 'monthly';
      case _RepeatOption.everyYear:
        return 'yearly';
      case _RepeatOption.custom:
        return _woCustomFrequency;
    }
  }

  int get _woInterval {
    switch (_woRepeat) {
      case _RepeatOption.every2Weeks:
        return 2;
      case _RepeatOption.custom:
        return _woCustomInterval;
      default:
        return 1;
    }
  }

  int? get _woDayOfWeek =>
      _woFrequency == 'weekly' ? _woDate.weekday - 1 : null;
  int? get _woDayOfMonth => _woFrequency == 'monthly' ? _woDate.day : null;

  String? get _woComputedEndDate => _woRepeat == _RepeatOption.never
      ? null
      : _woEndDate != null
          ? _formatDate(_woEndDate!)
          : null;

  // ── Derived params (inspection) ───────────────────────────────────────────────

  String get _frequency {
    switch (_repeat) {
      case _RepeatOption.never:
      case _RepeatOption.everyDay:
        return 'daily';
      case _RepeatOption.everyWeek:
      case _RepeatOption.every2Weeks:
        return 'weekly';
      case _RepeatOption.everyMonth:
        return 'monthly';
      case _RepeatOption.everyYear:
        return 'yearly';
      case _RepeatOption.custom:
        return _customFrequency;
    }
  }

  int get _interval {
    switch (_repeat) {
      case _RepeatOption.every2Weeks:
        return 2;
      case _RepeatOption.custom:
        return _customInterval;
      default:
        return 1;
    }
  }

  int? get _dayOfWeek => _frequency == 'weekly' ? _date.weekday - 1 : null;
  int? get _dayOfMonth => _frequency == 'monthly' ? _date.day : null;

  String? get _computedEndDate => _repeat == _RepeatOption.never
      ? _formatDate(_date)
      : _endDate != null
          ? _formatDate(_endDate!)
          : null;

  static const _repeatOptions = [
    (_RepeatOption.never, 'Does not repeat'),
    (_RepeatOption.everyDay, 'Every day'),
    (_RepeatOption.everyWeek, 'Every week'),
    (_RepeatOption.every2Weeks, 'Every 2 weeks'),
    (_RepeatOption.everyMonth, 'Every month'),
    (_RepeatOption.everyYear, 'Every year'),
    (_RepeatOption.custom, 'Custom'),
  ];

  // ── Helpers ───────────────────────────────────────────────────────────────────

  String _formatDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  String _displayDate(DateTime d) {
    const mo = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec'
    ];
    return '${mo[d.month - 1]} ${d.day}, ${d.year}';
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: Colors.red,
      behavior: SnackBarBehavior.floating,
    ));
  }

  IconData _typeIcon(String type) {
    switch (type) {
      case 'Inspection':
        return Icons.checklist_rounded;
      case 'Technical':
        return Icons.build_outlined;
      default:
        return Icons.work_outline_rounded;
    }
  }

  Color _typeColor(String type) {
    switch (type) {
      case 'Inspection':
        return AppColors.inProgressText;
      case 'Technical':
        return AppColors.accent;
      default:
        return AppColors.textSecondary;
    }
  }

  // ── Actions ───────────────────────────────────────────────────────────────────

  Future<void> _save() async {
    if (_tab == _Tab.workOrder && !_isEditing) {
      await _saveWorkOrder();
    } else {
      await _saveInspection();
    }
  }

  Future<void> _saveWorkOrder() async {
    if (_woTitleCtrl.text.trim().isEmpty) {
      _showError('Title is required');
      return;
    }
    if (_woDeptId.isEmpty) {
      _showError('Department is required');
      return;
    }

    setState(() => _saving = true);
    try {
      if (_woRepeat != _RepeatOption.never) {
        // Recurring WO → stored as a recurring inspection
        await _service.create(
          title: _woTitleCtrl.text.trim(),
          description: _woDescCtrl.text.trim(),
          location: _woLocationCtrl.text.trim(),
          departmentId: _woDeptId,
          frequency: _woFrequency,
          dayOfWeek: _woDayOfWeek,
          dayOfMonth: _woDayOfMonth,
          interval: _woInterval,
          startDate: _formatDate(_woDate),
          endDate: _woComputedEndDate,
          assignedFixerIds: _woTechIds,
        );
      } else {
        // Single WO
        final now = DateTime.now().toUtc();
        final jobNo =
            'WO-${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}-${now.millisecondsSinceEpoch % 10000}';
        await _woService.addWorkOrder(WorkOrder(
          id: '',
          jobNo: jobNo,
          title: _woTitleCtrl.text.trim(),
          description: _woDescCtrl.text.trim(),
          location: _woLocationCtrl.text.trim(),
          type: _woType,
          status: 'Pending',
          departmentId: _woDeptId,
          assignedTechnician: _woTechIds.isNotEmpty
              ? TechnicianAssignment(
                  id: _woTechIds.first,
                  fullName: _technicians
                          .where((t) => t.id == _woTechIds.first)
                          .firstOrNull
                          ?.fullName ??
                      '',
                  email: _technicians
                          .where((t) => t.id == _woTechIds.first)
                          .firstOrNull
                          ?.email ??
                      '',
                )
              : null,
          dateCreated: '',
          dateModified: '',
        ));
      }
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      _showError('Error: $e');
    }
  }

  Future<void> _saveInspection() async {
    if (_titleCtrl.text.trim().isEmpty) {
      _showError('Title is required');
      return;
    }
    if (_selectedDeptId.isEmpty) {
      _showError('Department is required');
      return;
    }

    setState(() => _saving = true);
    try {
      if (_isEditing) {
        await _service.update(
          widget.existing!.id,
          title: _titleCtrl.text.trim(),
          description: _descCtrl.text.trim(),
          location: _locationCtrl.text.trim(),
          departmentId: _selectedDeptId,
          frequency: _frequency,
          dayOfWeek: _dayOfWeek,
          dayOfMonth: _dayOfMonth,
          interval: _interval,
          startDate: _formatDate(_date),
          endDate: _computedEndDate,
          isActive: _isActive,
          type: _inspectionType,
          assignedFixerIds: _selectedTechIds,
        );
      } else {
        await _service.create(
          title: _titleCtrl.text.trim(),
          description: _descCtrl.text.trim(),
          location: _locationCtrl.text.trim(),
          departmentId: _selectedDeptId,
          frequency: _frequency,
          dayOfWeek: _dayOfWeek,
          dayOfMonth: _dayOfMonth,
          interval: _interval,
          startDate: _formatDate(_date),
          endDate: _computedEndDate,
          type: _inspectionType,
          assignedFixerIds: _selectedTechIds,
        );
      }
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      _showError('Error: $e');
    }
  }

  Future<void> _delete() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Inspection'),
        content: const Text(
            'This will stop future auto-generated work orders. Continue?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    setState(() => _deleting = true);
    try {
      await _service.delete(widget.existing!.id);
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _deleting = false);
      _showError('Error: $e');
    }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2024),
      lastDate: DateTime(2035),
    );
    if (picked != null)
      setState(() {
        _date = picked;
        _dateCtrl.text = _displayDate(picked);
      });
  }

  Future<void> _pickEndDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _endDate ?? _date.add(const Duration(days: 7)),
      firstDate: _date,
      lastDate: DateTime(2035),
    );
    if (picked != null)
      setState(() {
        _endDate = picked;
        _endDateCtrl.text = _displayDate(picked);
      });
  }

  Future<void> _pickWODate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _woDate,
      firstDate: DateTime(2024),
      lastDate: DateTime(2035),
    );
    if (picked != null)
      setState(() {
        _woDate = picked;
        _woDateCtrl.text = _displayDate(picked);
      });
  }

  Future<void> _pickWOEndDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _woEndDate ?? _woDate.add(const Duration(days: 7)),
      firstDate: _woDate,
      lastDate: DateTime(2035),
    );
    if (picked != null)
      setState(() {
        _woEndDate = picked;
        _woEndDateCtrl.text = _displayDate(picked);
      });
  }

  void _openTechSelector({bool isWO = false}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => TechnicianSelector(
        technicians: _technicians,
        selectedIds: isWO ? _woTechIds : _selectedTechIds,
        onChanged: (ids) {
          setState(() => isWO ? _woTechIds = ids : _selectedTechIds = ids);
        },
      ),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgPrimary,
      resizeToAvoidBottomInset: false,
      body: SafeArea(
        child: Column(
          children: [
            // ── Header — matches WO screen style ──────────────────────────────
            Container(
              color: AppColors.bgSurface,
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Column(
                children: [
                  Row(
                    children: [
                      // Back button — rounded rect matching WO screen
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
                          child: Icon(Icons.arrow_back_rounded,
                              size: 16, color: AppColors.textSecondary),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _isEditing ? 'Edit Inspection' : 'New Schedule',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textPrimary,
                                letterSpacing: -0.3,
                              ),
                            ),
                            if (!_isEditing) ...[
                              const SizedBox(height: 1),
                              AnimatedSwitcher(
                                duration: const Duration(milliseconds: 180),
                                child: Text(
                                  _tab == _Tab.workOrder
                                      ? 'Work Order'
                                      : 'Recurring Inspection',
                                  key: ValueKey(_tab),
                                  style: TextStyle(
                                      fontSize: 11,
                                      color: AppColors.textTertiary),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      // Delete button (edit mode)
                      if (_isEditing) ...[
                        GestureDetector(
                          onTap: _deleting ? null : _delete,
                          child: Container(
                            width: 34,
                            height: 34,
                            margin: const EdgeInsets.only(right: 8),
                            decoration: BoxDecoration(
                              color: AppColors.dangerBg,
                              borderRadius: BorderRadius.circular(9),
                              border: Border.all(
                                  color: AppColors.dangerBorder, width: 0.5),
                            ),
                            child: _deleting
                                ? Padding(
                                    padding: const EdgeInsets.all(9),
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: AppColors.dangerText),
                                  )
                                : Icon(Icons.delete_outline_rounded,
                                    size: 16, color: AppColors.dangerText),
                          ),
                        ),
                      ],
                      // Save button — accent tinted rounded rect
                      GestureDetector(
                        onTap: _saving ? null : _save,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                            color: _saving
                                ? AppColors.bgSurface2
                                : AppColors.accentBg,
                            borderRadius: BorderRadius.circular(9),
                            border: Border.all(
                              color: _saving
                                  ? AppColors.border2
                                  : AppColors.accent.withValues(alpha: 0.4),
                              width: 0.5,
                            ),
                          ),
                          child: _saving
                              ? Padding(
                                  padding: const EdgeInsets.all(9),
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2, color: AppColors.accent),
                                )
                              : Icon(Icons.check_rounded,
                                  size: 16, color: AppColors.accent),
                        ),
                      ),
                    ],
                  ),

                  // Tabs — underline style matching WO screen (new only)
                  if (!_isEditing) ...[
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        if (widget.userRole != 'technician')
                          _tabUnderline('Work order', _Tab.workOrder),
                        _tabUnderline('Inspection', _Tab.inspection),
                      ],
                    ),
                  ] else
                    const SizedBox(height: 12),
                ],
              ),
            ),
            Divider(height: 0, thickness: 0.5, color: AppColors.border),

            // ── Form content with animated tab switching ───────────────────────
            Expanded(
              child: _loadingData
                  ? Center(
                      child: CircularProgressIndicator(
                          color: AppColors.accent, strokeWidth: 2))
                  : AnimatedSwitcher(
                      duration: const Duration(milliseconds: 220),
                      transitionBuilder: (child, animation) => FadeTransition(
                        opacity: animation,
                        child: SlideTransition(
                          position: Tween<Offset>(
                            begin: const Offset(0, 0.02),
                            end: Offset.zero,
                          ).animate(animation),
                          child: child,
                        ),
                      ),
                      child: KeyedSubtree(
                        key: ValueKey(_tab),
                        child: (_tab == _Tab.workOrder && !_isEditing)
                            ? _buildWOForm()
                            : _buildInspectionForm(),
                      ),
                    ),
            ),

            // ── Sticky save bar ────────────────────────────────────────────────
            if (!_loadingData)
              Container(
                decoration: BoxDecoration(
                  color: AppColors.bgSurface,
                  border: Border(
                      top: BorderSide(color: AppColors.border, width: 0.5)),
                ),
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                child: SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    onPressed: _saving ? null : _save,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.accent,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      elevation: 0,
                    ),
                    child: _saving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        : Text(
                            _isEditing ? 'Update' : 'Create',
                            style: const TextStyle(
                                fontSize: 14, fontWeight: FontWeight.w600),
                          ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _tabUnderline(String label, _Tab tab) {
    final selected = _tab == tab;
    return GestureDetector(
      onTap: () => setState(() => _tab = tab),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.only(bottom: 10),
        margin: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: selected ? AppColors.accent : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            color: selected ? AppColors.accent : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }

  // ── Work Order form ───────────────────────────────────────────────────────────

  Widget _buildWOForm() {
    final deptName =
        _departments.where((d) => d.id == _woDeptId).firstOrNull?.name;
    final selectedWOTechs = _woTechIds
        .map((id) => _technicians.where((t) => t.id == id).firstOrNull)
        .whereType<AppUser>()
        .toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextFormField(
            controller: _woTitleCtrl,
            decoration: const InputDecoration(labelText: 'Title'),
          ),
          const SizedBox(height: 10),
          TextFormField(
            controller: _woDescCtrl,
            maxLines: 3,
            decoration: const InputDecoration(labelText: 'Description'),
          ),
          const SizedBox(height: 10),
          TextFormField(
            controller: _woLocationCtrl,
            decoration: const InputDecoration(labelText: 'Location'),
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<_RepeatOption>(
            value: _woRepeat,
            items: _repeatOptions
                .map((o) => DropdownMenuItem(value: o.$1, child: Text(o.$2)))
                .toList(),
            onChanged: (v) {
              if (v != null)
                setState(() {
                  _woRepeat = v;
                  if (v == _RepeatOption.never) {
                    _woEndDate = null;
                    _woEndDateCtrl.clear();
                  }
                });
            },
            decoration: const InputDecoration(labelText: 'Repeat'),
          ),
          const SizedBox(height: 10),
          TextFormField(
            controller: _woDateCtrl,
            readOnly: true,
            onTap: _pickWODate,
            decoration: const InputDecoration(
              labelText: 'Date',
              suffixIcon: Icon(Icons.calendar_today_outlined, size: 18),
            ),
          ),
          if (_woRepeat != _RepeatOption.never) ...[
            const SizedBox(height: 10),
            TextFormField(
              controller: _woEndDateCtrl,
              readOnly: true,
              onTap: _pickWOEndDate,
              decoration: InputDecoration(
                labelText: 'End Date',
                hintText: 'Never',
                suffixIcon: _woEndDate != null
                    ? GestureDetector(
                        onTap: () => setState(() {
                          _woEndDate = null;
                          _woEndDateCtrl.clear();
                        }),
                        child: const Icon(Icons.close_rounded, size: 18),
                      )
                    : const Icon(Icons.calendar_today_outlined, size: 18),
              ),
            ),
          ],
          if (_woRepeat == _RepeatOption.custom) ...[
            const SizedBox(height: 10),
            _inlineCustomPicker(
              freq: _woCustomFrequency,
              interval: _woCustomInterval,
              onFreq: (f) => setState(() => _woCustomFrequency = f),
              onInterval: (n) => setState(() => _woCustomInterval = n),
            ),
          ],
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            value: _woType,
            items: _woTypes
                .map((t) => DropdownMenuItem(
                      value: t,
                      child: Row(children: [
                        Icon(_typeIcon(t), size: 16, color: _typeColor(t)),
                        const SizedBox(width: 8),
                        Text(t),
                      ]),
                    ))
                .toList(),
            onChanged: (v) {
              if (v != null) setState(() => _woType = v);
            },
            decoration: const InputDecoration(labelText: 'Type'),
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            value: deptName,
            items: _departments
                .map(
                    (d) => DropdownMenuItem(value: d.name, child: Text(d.name)))
                .toList(),
            onChanged: (v) {
              if (v != null) {
                final dept = _departments.firstWhere((d) => d.name == v);
                setState(() => _woDeptId = dept.id);
              }
            },
            decoration: const InputDecoration(labelText: 'Department'),
          ),
          const SizedBox(height: 25),
          Text('Assign Technician',
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary)),
          const SizedBox(height: 10),
          ElevatedButton.icon(
            icon: const Icon(Icons.people),
            label: const Text('Select Technician'),
            onPressed: () => _openTechSelector(isWO: true),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            children: selectedWOTechs
                .map((tech) => Chip(
                      label: Text(tech.fullName ?? ''),
                      deleteIcon: const Icon(Icons.close),
                      onDeleted: () =>
                          setState(() => _woTechIds.remove(tech.id)),
                    ))
                .toList(),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  // ── Inspection form ───────────────────────────────────────────────────────────

  Widget _buildInspectionForm() {
    final deptName =
        _departments.where((d) => d.id == _selectedDeptId).firstOrNull?.name;
    final selectedTechs = _selectedTechIds
        .map((id) => _technicians.where((t) => t.id == id).firstOrNull)
        .whereType<AppUser>()
        .toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextFormField(
            controller: _titleCtrl,
            decoration: const InputDecoration(labelText: 'Title'),
          ),
          const SizedBox(height: 10),
          TextFormField(
            controller: _descCtrl,
            maxLines: 3,
            decoration: const InputDecoration(labelText: 'Description'),
          ),
          const SizedBox(height: 10),
          TextFormField(
            controller: _locationCtrl,
            decoration: const InputDecoration(labelText: 'Location'),
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<_RepeatOption>(
            value: _repeat,
            items: _repeatOptions
                .map((o) => DropdownMenuItem(value: o.$1, child: Text(o.$2)))
                .toList(),
            onChanged: (v) {
              if (v != null)
                setState(() {
                  _repeat = v;
                  if (v == _RepeatOption.never) {
                    _endDate = null;
                    _endDateCtrl.clear();
                  }
                });
            },
            decoration: const InputDecoration(labelText: 'Repeat'),
          ),
          const SizedBox(height: 10),
          TextFormField(
            controller: _dateCtrl,
            readOnly: true,
            onTap: _pickDate,
            decoration: const InputDecoration(
              labelText: 'Date',
              suffixIcon: Icon(Icons.calendar_today_outlined, size: 18),
            ),
          ),
          if (_repeat != _RepeatOption.never) ...[
            const SizedBox(height: 10),
            TextFormField(
              controller: _endDateCtrl,
              readOnly: true,
              onTap: _pickEndDate,
              decoration: InputDecoration(
                labelText: 'End Date',
                hintText: 'Never',
                suffixIcon: _endDate != null
                    ? GestureDetector(
                        onTap: () => setState(() {
                          _endDate = null;
                          _endDateCtrl.clear();
                        }),
                        child: const Icon(Icons.close_rounded, size: 18),
                      )
                    : const Icon(Icons.calendar_today_outlined, size: 18),
              ),
            ),
          ],
          if (_repeat == _RepeatOption.custom) ...[
            const SizedBox(height: 10),
            _inlineCustomPicker(
              freq: _customFrequency,
              interval: _customInterval,
              onFreq: (f) => setState(() => _customFrequency = f),
              onInterval: (n) => setState(() => _customInterval = n),
            ),
          ],
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            value: _inspectionType,
            items: _woTypes
                .map((t) => DropdownMenuItem(
                      value: t,
                      child: Row(children: [
                        Icon(_typeIcon(t), size: 16, color: _typeColor(t)),
                        const SizedBox(width: 8),
                        Text(t),
                      ]),
                    ))
                .toList(),
            onChanged: (v) {
              if (v != null) setState(() => _inspectionType = v);
            },
            decoration: const InputDecoration(labelText: 'Type'),
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            value: deptName,
            items: _departments
                .map(
                    (d) => DropdownMenuItem(value: d.name, child: Text(d.name)))
                .toList(),
            onChanged: (v) {
              if (v != null) {
                final dept = _departments.firstWhere((d) => d.name == v);
                setState(() => _selectedDeptId = dept.id);
              }
            },
            decoration: const InputDecoration(labelText: 'Department'),
          ),
          const SizedBox(height: 25),
          Text('Assign Technician',
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary)),
          const SizedBox(height: 10),
          ElevatedButton.icon(
            icon: const Icon(Icons.people),
            label: const Text('Select Technician'),
            onPressed: () => _openTechSelector(isWO: false),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            children: selectedTechs
                .map((tech) => Chip(
                      label: Text(tech.fullName ?? ''),
                      deleteIcon: const Icon(Icons.close),
                      onDeleted: () =>
                          setState(() => _selectedTechIds.remove(tech.id)),
                    ))
                .toList(),
          ),
          if (_isEditing) ...[
            const SizedBox(height: 16),
            Row(
              children: [
                Text('Active',
                    style: TextStyle(
                        fontSize: 14, color: AppColors.textSecondary)),
                const Spacer(),
                Switch.adaptive(
                  value: _isActive,
                  onChanged: (v) => setState(() => _isActive = v),
                  activeThumbColor: AppColors.accent,
                  activeTrackColor: AppColors.accent.withValues(alpha: 0.4),
                ),
              ],
            ),
          ],
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  // ── Inline pickers ────────────────────────────────────────────────────────────

  Widget _inlineCustomPicker({
    required String freq,
    required int interval,
    required void Function(String) onFreq,
    required void Function(int) onInterval,
  }) {
    const freqs = ['daily', 'weekly', 'monthly', 'yearly'];
    final unitLabel = {
          'daily': interval == 1 ? 'day' : 'days',
          'weekly': interval == 1 ? 'week' : 'weeks',
          'monthly': interval == 1 ? 'month' : 'months',
          'yearly': interval == 1 ? 'year' : 'years',
        }[freq] ??
        '';

    return Container(
      color: AppColors.bgSurface2,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Frequency',
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textTertiary)),
          const SizedBox(height: 8),
          Row(
            children: freqs.asMap().entries.map((e) {
              final f = e.value;
              final sel = freq == f;
              return Expanded(
                child: Padding(
                  padding: EdgeInsets.only(right: e.key < 3 ? 6 : 0),
                  child: GestureDetector(
                    onTap: () => onFreq(f),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(
                        color: sel ? AppColors.accent : AppColors.bgSurface,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: sel ? AppColors.accent : AppColors.border,
                          width: sel ? 1.5 : 0.5,
                        ),
                      ),
                      child: Center(
                        child: Text(
                          f[0].toUpperCase() + f.substring(1),
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: sel ? Colors.white : AppColors.textSecondary,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 14),
          Text('Every',
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textTertiary)),
          const SizedBox(height: 8),
          Row(
            children: [
              _stepBtn(Icons.remove, () {
                if (interval > 1) onInterval(interval - 1);
              }),
              const SizedBox(width: 10),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  decoration: BoxDecoration(
                    color: AppColors.bgSurface,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.border, width: 0.5),
                  ),
                  child: Center(
                    child: Text('$interval',
                        style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary)),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              _stepBtn(Icons.add, () {
                if (interval < 99) onInterval(interval + 1);
              }),
              const SizedBox(width: 10),
              Text(unitLabel,
                  style:
                      TextStyle(fontSize: 13, color: AppColors.textSecondary)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _stepBtn(IconData icon, VoidCallback onTap) => GestureDetector(
        onTap: onTap,
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: AppColors.bgSurface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.border, width: 0.5),
          ),
          child: Icon(icon, size: 16, color: AppColors.textPrimary),
        ),
      );
}
