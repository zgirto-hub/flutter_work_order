import 'package:flutter/material.dart';
import '../../models/recurring_inspection.dart';
import '../../models/department.dart';
import '../../models/user.dart';
import '../../models/work_order.dart';
import '../../models/technician_assignment.dart';
import '../../services/recurring_inspection_service.dart';
import '../../services/department_service.dart';
import '../../services/user_service.dart';
import '../../services/work_order_service.dart';
import '../../widgets/technician_selector.dart';
import '../../theme/app_theme.dart';

enum _RepeatOption { never, everyDay, everyWeek, every2Weeks, everyMonth, everyYear, custom }
enum _Tab { workOrder, inspection }

class AddRecurringInspectionScreen extends StatefulWidget {
  final String userRole;
  final RecurringInspection? existing;

  const AddRecurringInspectionScreen({
    super.key,
    required this.userRole,
    this.existing,
  });

  @override
  State<AddRecurringInspectionScreen> createState() => _AddRecurringInspectionScreenState();
}

class _AddRecurringInspectionScreenState extends State<AddRecurringInspectionScreen> {
  final _service           = RecurringInspectionService();
  final _departmentService = DepartmentService();
  final _userService       = UserService();
  final _woService         = WorkOrderService();

  // Tab (only used when creating new)
  _Tab _tab = _Tab.workOrder;

  // Shared data
  List<Department> _departments = [];
  List<AppUser>    _technicians = [];
  bool _loadingData = true;
  bool _saving      = false;
  bool _deleting    = false;

  bool get _isEditing => widget.existing != null;

  // ── Inspection state ─────────────────────────────────────────────────────────
  final _titleCtrl    = TextEditingController();
  final _descCtrl     = TextEditingController();
  final _locationCtrl = TextEditingController();
  String        _selectedDeptId   = '';
  String        _inspectionType   = 'Inspection';
  List<String>  _selectedTechIds  = [];
  DateTime      _date             = DateTime.now();
  DateTime?     _endDate;
  _RepeatOption _repeat           = _RepeatOption.never;
  String        _customFrequency  = 'daily';
  int           _customInterval   = 1;
  bool          _isActive         = true;
  bool          _showRepeatPicker = false;

  // ── Work Order state ─────────────────────────────────────────────────────────
  final _woTitleCtrl    = TextEditingController();
  final _woDescCtrl     = TextEditingController();
  final _woLocationCtrl = TextEditingController();
  String       _woDeptId  = '';
  List<String> _woTechIds = [];
  String       _woType    = 'Technical';
  DateTime      _woDate            = DateTime.now();
  DateTime?     _woEndDate;
  _RepeatOption _woRepeat          = _RepeatOption.never;
  String        _woCustomFrequency = 'daily';
  int           _woCustomInterval  = 1;
  bool          _woShowRepeatPicker = false;

  static const _woTypes = ['Technical', 'Inspection', 'Other'];

  // ── Init ─────────────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    if (widget.userRole == 'technician') _tab = _Tab.inspection;
    if (_isEditing) {
      _tab = _Tab.inspection;
      final e = widget.existing!;
      _titleCtrl.text    = e.title;
      _descCtrl.text     = e.description;
      _locationCtrl.text = e.location;
      _selectedDeptId    = e.departmentId;
      _inspectionType    = e.type;
      _isActive          = e.isActive;
      _selectedTechIds   = e.assignees.map((a) => a.id).toList();
      _date = DateTime.tryParse(e.startDate) ?? DateTime.now();
      _endDate = (e.endDate != null && e.endDate != e.startDate)
          ? DateTime.tryParse(e.endDate!)
          : null;

      if (e.endDate == e.startDate) {
        _repeat = _RepeatOption.never;
      } else if (e.frequency == 'daily'   && (e.interval ?? 1) == 1) {
        _repeat = _RepeatOption.everyDay;
      } else if (e.frequency == 'weekly'  && (e.interval ?? 1) == 1) {
        _repeat = _RepeatOption.everyWeek;
      } else if (e.frequency == 'weekly'  && (e.interval ?? 1) == 2) {
        _repeat = _RepeatOption.every2Weeks;
      } else if (e.frequency == 'monthly' && (e.interval ?? 1) == 1) {
        _repeat = _RepeatOption.everyMonth;
      } else if (e.frequency == 'yearly'  && (e.interval ?? 1) == 1) {
        _repeat = _RepeatOption.everyYear;
      } else {
        _repeat          = _RepeatOption.custom;
        _customFrequency = e.frequency;
        _customInterval  = e.interval ?? 1;
      }
    }
    _loadFormData();
  }

  Future<void> _loadFormData() async {
    try {
      final depts = await _departmentService.fetchDepartments(isActive: true);
      final techs = await _userService.fetchUsers();
      if (!mounted) return;
      setState(() {
        _departments = depts;
        _technicians = techs.where((u) => u.userType == UserType.technician).toList();
        if (_selectedDeptId.isEmpty && depts.isNotEmpty) _selectedDeptId = depts.first.id;
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
    super.dispose();
  }

  // ── Derived params (work order repeat) ───────────────────────────────────────

  String get _woFrequency {
    switch (_woRepeat) {
      case _RepeatOption.never:
      case _RepeatOption.everyDay:    return 'daily';
      case _RepeatOption.everyWeek:
      case _RepeatOption.every2Weeks: return 'weekly';
      case _RepeatOption.everyMonth:  return 'monthly';
      case _RepeatOption.everyYear:   return 'yearly';
      case _RepeatOption.custom:      return _woCustomFrequency;
    }
  }

  int get _woInterval {
    switch (_woRepeat) {
      case _RepeatOption.every2Weeks: return 2;
      case _RepeatOption.custom:      return _woCustomInterval;
      default:                        return 1;
    }
  }

  int? get _woDayOfWeek  => _woFrequency == 'weekly'  ? _woDate.weekday - 1 : null;
  int? get _woDayOfMonth => _woFrequency == 'monthly' ? _woDate.day         : null;

  String? get _woComputedEndDate =>
      _woRepeat == _RepeatOption.never
          ? null
          : _woEndDate != null ? _formatDate(_woEndDate!) : null;

  String get _woRepeatLabel {
    const wd = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    const mo = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    switch (_woRepeat) {
      case _RepeatOption.never:       return 'Does not repeat';
      case _RepeatOption.everyDay:    return 'Daily';
      case _RepeatOption.everyWeek:   return 'Every week on ${wd[_woDate.weekday - 1]}';
      case _RepeatOption.every2Weeks: return 'Every 2 weeks on ${wd[_woDate.weekday - 1]}';
      case _RepeatOption.everyMonth:  return 'Monthly on day ${_woDate.day}';
      case _RepeatOption.everyYear:
        return 'Annually on ${mo[_woDate.month - 1]} ${_woDate.day}';
      case _RepeatOption.custom:
        final base = {'daily':'day','weekly':'week','monthly':'month','yearly':'year'}[_woCustomFrequency] ?? _woCustomFrequency;
        final unit = _woCustomInterval == 1 ? base : '${base}s';
        return 'Every $_woCustomInterval $unit';
    }
  }

  // ── Derived params (inspection) ───────────────────────────────────────────────

  String get _frequency {
    switch (_repeat) {
      case _RepeatOption.never:
      case _RepeatOption.everyDay:    return 'daily';
      case _RepeatOption.everyWeek:
      case _RepeatOption.every2Weeks: return 'weekly';
      case _RepeatOption.everyMonth:  return 'monthly';
      case _RepeatOption.everyYear:   return 'yearly';
      case _RepeatOption.custom:      return _customFrequency;
    }
  }

  int get _interval {
    switch (_repeat) {
      case _RepeatOption.every2Weeks: return 2;
      case _RepeatOption.custom:      return _customInterval;
      default:                        return 1;
    }
  }

  int? get _dayOfWeek  => _frequency == 'weekly'  ? _date.weekday - 1 : null;
  int? get _dayOfMonth => _frequency == 'monthly' ? _date.day         : null;

  String? get _computedEndDate =>
      _repeat == _RepeatOption.never
          ? _formatDate(_date)
          : _endDate != null ? _formatDate(_endDate!) : null;

  // ── Labels ────────────────────────────────────────────────────────────────────

  String get _repeatLabel {
    const wd = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    const mo = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    switch (_repeat) {
      case _RepeatOption.never:       return 'Does not repeat';
      case _RepeatOption.everyDay:    return 'Daily';
      case _RepeatOption.everyWeek:   return 'Every week on ${wd[_date.weekday - 1]}';
      case _RepeatOption.every2Weeks: return 'Every 2 weeks on ${wd[_date.weekday - 1]}';
      case _RepeatOption.everyMonth:  return 'Monthly on day ${_date.day}';
      case _RepeatOption.everyYear:
        return 'Annually on ${mo[_date.month - 1]} ${_date.day}';
      case _RepeatOption.custom:
        final base = {'daily':'day','weekly':'week','monthly':'month','yearly':'year'}[_customFrequency] ?? _customFrequency;
        final unit = _customInterval == 1 ? base : '${base}s';
        return 'Every $_customInterval $unit';
    }
  }

  static const _repeatOptions = [
    (_RepeatOption.never,       'Does not repeat'),
    (_RepeatOption.everyDay,    'Every day'),
    (_RepeatOption.everyWeek,   'Every week'),
    (_RepeatOption.every2Weeks, 'Every 2 weeks'),
    (_RepeatOption.everyMonth,  'Every month'),
    (_RepeatOption.everyYear,   'Every year'),
    (_RepeatOption.custom,      'Custom'),
  ];

  // ── Helpers ───────────────────────────────────────────────────────────────────

  String _formatDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  String _displayDate(DateTime d) {
    const mo = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
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
      case 'Inspection': return Icons.checklist_rounded;
      case 'Technical':  return Icons.build_outlined;
      default:           return Icons.work_outline_rounded;
    }
  }

  Color _typeColor(String type) {
    switch (type) {
      case 'Inspection': return AppColors.inProgressText;
      case 'Technical':  return AppColors.accent;
      default:           return AppColors.textSecondary;
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
    if (_woTitleCtrl.text.trim().isEmpty) { _showError('Title is required'); return; }
    if (_woDeptId.isEmpty) { _showError('Department is required'); return; }

    setState(() => _saving = true);
    try {
      if (_woRepeat != _RepeatOption.never) {
        // Recurring WO → stored as a recurring inspection
        await _service.create(
          title:            _woTitleCtrl.text.trim(),
          description:      _woDescCtrl.text.trim(),
          location:         _woLocationCtrl.text.trim(),
          departmentId:     _woDeptId,
          frequency:        _woFrequency,
          dayOfWeek:        _woDayOfWeek,
          dayOfMonth:       _woDayOfMonth,
          interval:         _woInterval,
          startDate:        _formatDate(_woDate),
          endDate:          _woComputedEndDate,
          assignedFixerIds: _woTechIds,
        );
      } else {
        // Single WO
        final now   = DateTime.now();
        final jobNo = 'WO-${now.year}${now.month.toString().padLeft(2,'0')}${now.day.toString().padLeft(2,'0')}-${now.millisecondsSinceEpoch % 10000}';
        await _woService.addWorkOrder(WorkOrder(
          id: '',
          jobNo: jobNo,
          title: _woTitleCtrl.text.trim(),
          description: _woDescCtrl.text.trim(),
          location: _woLocationCtrl.text.trim(),
          type: _woType,
          status: 'Pending',
          departmentId: _woDeptId,
          assignedTechnicians: _woTechIds.map((id) {
            final tech = _technicians.where((t) => t.id == id).firstOrNull;
            return TechnicianAssignment(id: id, fullName: tech?.fullName ?? '', email: tech?.email ?? '');
          }).toList(),
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
    if (_titleCtrl.text.trim().isEmpty) { _showError('Title is required'); return; }
    if (_selectedDeptId.isEmpty) { _showError('Department is required'); return; }

    setState(() => _saving = true);
    try {
      if (_isEditing) {
        await _service.update(
          widget.existing!.id,
          title:            _titleCtrl.text.trim(),
          description:      _descCtrl.text.trim(),
          location:         _locationCtrl.text.trim(),
          departmentId:     _selectedDeptId,
          frequency:        _frequency,
          dayOfWeek:        _dayOfWeek,
          dayOfMonth:       _dayOfMonth,
          interval:         _interval,
          startDate:        _formatDate(_date),
          endDate:          _computedEndDate,
          isActive:         _isActive,
          type:             _inspectionType,
          assignedFixerIds: _selectedTechIds,
        );
      } else {
        await _service.create(
          title:            _titleCtrl.text.trim(),
          description:      _descCtrl.text.trim(),
          location:         _locationCtrl.text.trim(),
          departmentId:     _selectedDeptId,
          frequency:        _frequency,
          dayOfWeek:        _dayOfWeek,
          dayOfMonth:       _dayOfMonth,
          interval:         _interval,
          startDate:        _formatDate(_date),
          endDate:          _computedEndDate,
          type:             _inspectionType,
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
        content: const Text('This will stop future auto-generated work orders. Continue?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
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
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _pickEndDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _endDate ?? _date.add(const Duration(days: 7)),
      firstDate: _date,
      lastDate: DateTime(2035),
    );
    if (picked != null) setState(() => _endDate = picked);
  }

  Future<void> _pickWODate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _woDate,
      firstDate: DateTime(2024),
      lastDate: DateTime(2035),
    );
    if (picked != null) setState(() => _woDate = picked);
  }

  Future<void> _pickWOEndDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _woEndDate ?? _woDate.add(const Duration(days: 7)),
      firstDate: _woDate,
      lastDate: DateTime(2035),
    );
    if (picked != null) setState(() => _woEndDate = picked);
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
          Navigator.pop(context);
        },
      ),
    );
  }

  void _showDepartmentPicker({bool isWO = false}) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: BoxDecoration(
          color: AppColors.bgSurface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.only(top: 16, bottom: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(
              child: Container(
                width: 36, height: 4,
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(color: AppColors.border2, borderRadius: BorderRadius.circular(2)),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('Department',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
              ),
            ),
            ..._departments.map((d) => InkWell(
              onTap: () {
                setState(() => isWO ? _woDeptId = d.id : _selectedDeptId = d.id);
                Navigator.pop(ctx);
              },
              child: Container(
                height: 50,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    Text(d.name, style: TextStyle(fontSize: 15, color: AppColors.textPrimary)),
                    const Spacer(),
                    if ((isWO ? _woDeptId : _selectedDeptId) == d.id)
                      Icon(Icons.check_rounded, size: 18, color: AppColors.accent),
                  ],
                ),
              ),
            )),
          ],
        ),
      ),
    );
  }

  void _showInspectionTypePicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: BoxDecoration(
          color: AppColors.bgSurface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.only(top: 16, bottom: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(
              child: Container(
                width: 36, height: 4,
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(color: AppColors.border2, borderRadius: BorderRadius.circular(2)),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('Type',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
              ),
            ),
            ..._woTypes.map((t) => InkWell(
              onTap: () {
                setState(() => _inspectionType = t);
                Navigator.pop(ctx);
              },
              child: Container(
                height: 50,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    Icon(_typeIcon(t), size: 16, color: _typeColor(t)),
                    const SizedBox(width: 10),
                    Text(t, style: TextStyle(fontSize: 15, color: AppColors.textPrimary)),
                    const Spacer(),
                    if (_inspectionType == t)
                      Icon(Icons.check_rounded, size: 18, color: AppColors.accent),
                  ],
                ),
              ),
            )),
          ],
        ),
      ),
    );
  }

  void _showTypePicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: BoxDecoration(
          color: AppColors.bgSurface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.only(top: 16, bottom: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(
              child: Container(
                width: 36, height: 4,
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(color: AppColors.border2, borderRadius: BorderRadius.circular(2)),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('Type',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
              ),
            ),
            ..._woTypes.map((t) => InkWell(
              onTap: () {
                setState(() => _woType = t);
                Navigator.pop(ctx);
              },
              child: Container(
                height: 50,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    Icon(_typeIcon(t), size: 16, color: _typeColor(t)),
                    const SizedBox(width: 10),
                    Text(t, style: TextStyle(fontSize: 15, color: AppColors.textPrimary)),
                    const Spacer(),
                    if (_woType == t)
                      Icon(Icons.check_rounded, size: 18, color: AppColors.accent),
                  ],
                ),
              ),
            )),
          ],
        ),
      ),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgPrimary,
      resizeToAvoidBottomInset: true,
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
                          width: 34, height: 34,
                          decoration: BoxDecoration(
                            color: AppColors.bgSurface2,
                            borderRadius: BorderRadius.circular(9),
                            border: Border.all(color: AppColors.border2, width: 0.5),
                          ),
                          child: Icon(Icons.arrow_back_rounded, size: 16, color: AppColors.textSecondary),
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
                                fontSize: 16, fontWeight: FontWeight.w600,
                                color: AppColors.textPrimary, letterSpacing: -0.3,
                              ),
                            ),
                            if (!_isEditing) ...[
                              const SizedBox(height: 1),
                              AnimatedSwitcher(
                                duration: const Duration(milliseconds: 180),
                                child: Text(
                                  _tab == _Tab.workOrder ? 'Work Order' : 'Recurring Inspection',
                                  key: ValueKey(_tab),
                                  style: TextStyle(fontSize: 11, color: AppColors.textTertiary),
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
                            width: 34, height: 34,
                            margin: const EdgeInsets.only(right: 8),
                            decoration: BoxDecoration(
                              color: AppColors.dangerBg,
                              borderRadius: BorderRadius.circular(9),
                              border: Border.all(color: AppColors.dangerBorder, width: 0.5),
                            ),
                            child: _deleting
                                ? Padding(
                                    padding: const EdgeInsets.all(9),
                                    child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.dangerText),
                                  )
                                : Icon(Icons.delete_outline_rounded, size: 16, color: AppColors.dangerText),
                          ),
                        ),
                      ],
                      // Save button — accent tinted rounded rect
                      GestureDetector(
                        onTap: _saving ? null : _save,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          width: 34, height: 34,
                          decoration: BoxDecoration(
                            color: _saving ? AppColors.bgSurface2 : AppColors.accentBg,
                            borderRadius: BorderRadius.circular(9),
                            border: Border.all(
                              color: _saving ? AppColors.border2 : AppColors.accent.withValues(alpha: 0.4),
                              width: 0.5,
                            ),
                          ),
                          child: _saving
                              ? Padding(
                                  padding: const EdgeInsets.all(9),
                                  child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.accent),
                                )
                              : Icon(Icons.check_rounded, size: 16, color: AppColors.accent),
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
                  ? Center(child: CircularProgressIndicator(color: AppColors.accent, strokeWidth: 2))
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
                  border: Border(top: BorderSide(color: AppColors.border, width: 0.5)),
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
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      elevation: 0,
                    ),
                    child: _saving
                        ? const SizedBox(
                            width: 20, height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : Text(
                            _isEditing ? 'Update' : 'Create',
                            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
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
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          _group([
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
              child: TextField(
                controller: _woTitleCtrl,
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500, color: AppColors.textPrimary),
                decoration: InputDecoration(
                  hintText: 'Title',
                  hintStyle: TextStyle(fontSize: 18, fontWeight: FontWeight.w400, color: AppColors.textTertiary),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
            _divider(),
            _inlineTextField(_woDescCtrl, 'Description', 'Add description', maxLines: 3),
            _divider(),
            _inlineTextField(_woLocationCtrl, 'Location', 'Add location'),
          ]),

          const SizedBox(height: 8),

          _group([
            _tapRow(
              label: 'Date',
              value: _displayDate(_woDate),
              valueColor: AppColors.accent,
              onTap: _pickWODate,
            ),
            _divider(),

            // Repeat row
            InkWell(
              onTap: () => setState(() => _woShowRepeatPicker = !_woShowRepeatPicker),
              child: Container(
                constraints: const BoxConstraints(minHeight: 52),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                child: Row(
                  children: [
                    Text('Repeat', style: TextStyle(fontSize: 14, color: AppColors.textSecondary)),
                    const Spacer(),
                    Flexible(
                      child: Text(
                        _woRepeatLabel,
                        style: TextStyle(fontSize: 14, color: AppColors.textPrimary),
                        textAlign: TextAlign.right,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 6),
                    AnimatedRotation(
                      turns: _woShowRepeatPicker ? 0.25 : 0,
                      duration: const Duration(milliseconds: 200),
                      child: Icon(Icons.chevron_right, size: 16, color: AppColors.textTertiary),
                    ),
                  ],
                ),
              ),
            ),

            AnimatedSize(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeInOut,
              child: _woShowRepeatPicker
                  ? Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Divider(height: 0, thickness: 0.5, color: AppColors.border),
                        _inlineRepeatPicker(
                          current: _woRepeat,
                          onSelect: (opt) => setState(() {
                            _woRepeat = opt;
                            _woShowRepeatPicker = false;
                            if (opt == _RepeatOption.never) _woEndDate = null;
                          }),
                        ),
                      ],
                    )
                  : const SizedBox.shrink(),
            ),

            if (_woRepeat == _RepeatOption.custom) ...[
              _divider(),
              _inlineCustomPicker(
                freq: _woCustomFrequency,
                interval: _woCustomInterval,
                onFreq: (f) => setState(() => _woCustomFrequency = f),
                onInterval: (n) => setState(() => _woCustomInterval = n),
              ),
            ],

            if (_woRepeat != _RepeatOption.never) ...[
              _divider(),
              _woEndRepeatRow(),
            ],
          ]),

          const SizedBox(height: 8),

          _group([
            _tapRow(
              label: 'Type',
              value: _woType,
              leading: Icon(_typeIcon(_woType), size: 15, color: _typeColor(_woType)),
              onTap: _showTypePicker,
            ),
            _divider(),
            _tapRow(
              label: 'Department',
              value: _departments.where((d) => d.id == _woDeptId).firstOrNull?.name ?? 'Select',
              valueColor: _woDeptId.isEmpty ? AppColors.textTertiary : null,
              onTap: () => _showDepartmentPicker(isWO: true),
            ),
          ]),

          const SizedBox(height: 8),

          _group([
            _techRow(isWO: true),
          ]),

          const SizedBox(height: 8),
        ],
      ),
    );
  }

  // ── Inspection form ───────────────────────────────────────────────────────────

  Widget _buildInspectionForm() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // Group 1: Title / Description / Location
          _group([
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
              child: TextField(
                controller: _titleCtrl,
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500, color: AppColors.textPrimary),
                decoration: InputDecoration(
                  hintText: 'Title',
                  hintStyle: TextStyle(fontSize: 18, fontWeight: FontWeight.w400, color: AppColors.textTertiary),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
            _divider(),
            _inlineTextField(_descCtrl, 'Description', 'Add description', maxLines: 3),
            _divider(),
            _inlineTextField(_locationCtrl, 'Location', 'Add location'),
          ]),

          const SizedBox(height: 8),

          // Group 2: Date / Repeat
          _group([
            _tapRow(
              label: 'Date',
              value: _displayDate(_date),
              valueColor: AppColors.accent,
              onTap: _pickDate,
            ),
            _divider(),

            InkWell(
              onTap: () => setState(() => _showRepeatPicker = !_showRepeatPicker),
              child: Container(
                constraints: const BoxConstraints(minHeight: 52),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                child: Row(
                  children: [
                    Text('Repeat', style: TextStyle(fontSize: 14, color: AppColors.textSecondary)),
                    const Spacer(),
                    Flexible(
                      child: Text(
                        _repeatLabel,
                        style: TextStyle(fontSize: 14, color: AppColors.textPrimary),
                        textAlign: TextAlign.right,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 6),
                    AnimatedRotation(
                      turns: _showRepeatPicker ? 0.25 : 0,
                      duration: const Duration(milliseconds: 200),
                      child: Icon(Icons.chevron_right, size: 16, color: AppColors.textTertiary),
                    ),
                  ],
                ),
              ),
            ),

            AnimatedSize(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeInOut,
              child: _showRepeatPicker
                  ? Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Divider(height: 0, thickness: 0.5, color: AppColors.border),
                        _inlineRepeatPicker(
                          current: _repeat,
                          onSelect: (opt) => setState(() {
                            _repeat = opt;
                            _showRepeatPicker = false;
                            if (opt == _RepeatOption.never) _endDate = null;
                          }),
                        ),
                      ],
                    )
                  : const SizedBox.shrink(),
            ),

            if (_repeat == _RepeatOption.custom) ...[
              _divider(),
              _inlineCustomPicker(
                freq: _customFrequency,
                interval: _customInterval,
                onFreq: (f) => setState(() => _customFrequency = f),
                onInterval: (n) => setState(() => _customInterval = n),
              ),
            ],

            if (_repeat != _RepeatOption.never) ...[
              _divider(),
              _endRepeatRow(),
            ],
          ]),

          const SizedBox(height: 8),

          // Group 3: Type / Department
          _group([
            _tapRow(
              label: 'Type',
              value: _inspectionType,
              leading: Icon(_typeIcon(_inspectionType), size: 15, color: _typeColor(_inspectionType)),
              onTap: _showInspectionTypePicker,
            ),
            _divider(),
            _tapRow(
              label: 'Department',
              value: _departments.where((d) => d.id == _selectedDeptId).firstOrNull?.name ?? 'Select',
              valueColor: _selectedDeptId.isEmpty ? AppColors.textTertiary : null,
              onTap: () => _showDepartmentPicker(),
            ),
          ]),

          const SizedBox(height: 8),

          // Group 4: Technicians
          _group([
            _techRow(isWO: false),
          ]),

          if (_isEditing) ...[
            const SizedBox(height: 8),
            _group([
              Container(
                height: 52,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Text('Active', style: TextStyle(fontSize: 14, color: AppColors.textSecondary)),
                    const Spacer(),
                    Switch.adaptive(
                      value: _isActive,
                      onChanged: (v) => setState(() => _isActive = v),
                      activeThumbColor: AppColors.accent,
                      activeTrackColor: AppColors.accent.withValues(alpha: 0.4),
                    ),
                  ],
                ),
              ),
            ]),
          ],

          const SizedBox(height: 8),
        ],
      ),
    );
  }

  // ── Inline pickers ────────────────────────────────────────────────────────────

  Widget _inlineRepeatPicker({
    required _RepeatOption current,
    required void Function(_RepeatOption) onSelect,
  }) {
    return Container(
      color: AppColors.bgSurface2,
      child: Column(
        children: _repeatOptions.map((item) {
          final option   = item.$1;
          final label    = item.$2;
          final selected = current == option;
          return InkWell(
            onTap: () => onSelect(option),
            child: Container(
              height: 44,
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Row(
                children: [
                  Text(label,
                    style: TextStyle(
                      fontSize: 14,
                      color: selected ? AppColors.accent : AppColors.textPrimary,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                    ),
                  ),
                  const Spacer(),
                  if (selected) Icon(Icons.check_rounded, size: 16, color: AppColors.accent),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _inlineCustomPicker({
    required String freq,
    required int interval,
    required void Function(String) onFreq,
    required void Function(int) onInterval,
  }) {
    const freqs = ['daily', 'weekly', 'monthly', 'yearly'];
    final unitLabel = {
      'daily':   interval == 1 ? 'day'   : 'days',
      'weekly':  interval == 1 ? 'week'  : 'weeks',
      'monthly': interval == 1 ? 'month' : 'months',
      'yearly':  interval == 1 ? 'year'  : 'years',
    }[freq] ?? '';

    return Container(
      color: AppColors.bgSurface2,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Frequency',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textTertiary)),
          const SizedBox(height: 8),
          Row(
            children: freqs.asMap().entries.map((e) {
              final f   = e.value;
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
                            fontSize: 11, fontWeight: FontWeight.w600,
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
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textTertiary)),
          const SizedBox(height: 8),
          Row(
            children: [
              _stepBtn(Icons.remove, () { if (interval > 1) onInterval(interval - 1); }),
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
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              _stepBtn(Icons.add, () { if (interval < 99) onInterval(interval + 1); }),
              const SizedBox(width: 10),
              Text(unitLabel, style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _stepBtn(IconData icon, VoidCallback onTap) => GestureDetector(
    onTap: onTap,
    child: Container(
      width: 40, height: 40,
      decoration: BoxDecoration(
        color: AppColors.bgSurface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border, width: 0.5),
      ),
      child: Icon(icon, size: 16, color: AppColors.textPrimary),
    ),
  );

  // ── Row / Group helpers ───────────────────────────────────────────────────────

  Widget _group(List<Widget> rows) => Container(
    decoration: BoxDecoration(
      color: AppColors.bgSurface,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: AppColors.border, width: 0.5),
      boxShadow: AppShadows.cardLight,
    ),
    child: ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Column(children: rows),
    ),
  );

  Widget _divider() => Divider(height: 0, thickness: 0.5, indent: 16, color: AppColors.border);

  Widget _inlineTextField(TextEditingController ctrl, String label, String hint, {int maxLines = 1}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      child: Row(
        crossAxisAlignment: maxLines > 1 ? CrossAxisAlignment.start : CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 100,
            child: Padding(
              padding: EdgeInsets.only(top: maxLines > 1 ? 14 : 0),
              child: Text(label, style: TextStyle(fontSize: 14, color: AppColors.textSecondary)),
            ),
          ),
          Expanded(
            child: TextField(
              controller: ctrl,
              maxLines: maxLines,
              style: TextStyle(fontSize: 14, color: AppColors.textPrimary),
              decoration: InputDecoration(
                hintText: hint,
                hintStyle: TextStyle(fontSize: 14, color: AppColors.textTertiary),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tapRow({
    required String label,
    required String value,
    required VoidCallback onTap,
    Color? valueColor,
    Widget? leading,
  }) {
    return InkWell(
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 52),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            if (leading != null) ...[leading, const SizedBox(width: 8)],
            Text(label, style: TextStyle(fontSize: 14, color: AppColors.textSecondary)),
            const Spacer(),
            Flexible(
              child: Text(value,
                style: TextStyle(fontSize: 14, color: valueColor ?? AppColors.textPrimary),
                textAlign: TextAlign.right,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 6),
            Icon(Icons.chevron_right, size: 16, color: AppColors.textTertiary),
          ],
        ),
      ),
    );
  }

  Widget _endRepeatRow() {
    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Text('End Repeat', style: TextStyle(fontSize: 14, color: AppColors.textSecondary)),
          const Spacer(),
          GestureDetector(
            onTap: _pickEndDate,
            child: Text(
              _endDate != null ? _displayDate(_endDate!) : 'Never',
              style: TextStyle(
                fontSize: 14,
                color: _endDate != null ? AppColors.accent : AppColors.textTertiary,
              ),
            ),
          ),
          if (_endDate != null) ...[
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () => setState(() => _endDate = null),
              child: Icon(Icons.close_rounded, size: 16, color: AppColors.textTertiary),
            ),
          ],
          const SizedBox(width: 2),
        ],
      ),
    );
  }

  Widget _woEndRepeatRow() {
    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Text('End Repeat', style: TextStyle(fontSize: 14, color: AppColors.textSecondary)),
          const Spacer(),
          GestureDetector(
            onTap: _pickWOEndDate,
            child: Text(
              _woEndDate != null ? _displayDate(_woEndDate!) : 'Never',
              style: TextStyle(
                fontSize: 14,
                color: _woEndDate != null ? AppColors.accent : AppColors.textTertiary,
              ),
            ),
          ),
          if (_woEndDate != null) ...[
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () => setState(() => _woEndDate = null),
              child: Icon(Icons.close_rounded, size: 16, color: AppColors.textTertiary),
            ),
          ],
          const SizedBox(width: 2),
        ],
      ),
    );
  }

  Widget _techRow({required bool isWO}) {
    final ids   = isWO ? _woTechIds : _selectedTechIds;
    final names = ids
        .map((id) => _technicians.where((t) => t.id == id).firstOrNull?.fullName ?? id)
        .toList();
    return InkWell(
      onTap: () => _openTechSelector(isWO: isWO),
      child: Container(
        constraints: const BoxConstraints(minHeight: 52),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Text('Technicians', style: TextStyle(fontSize: 14, color: AppColors.textSecondary)),
            const Spacer(),
            Flexible(
              child: Text(
                names.isEmpty ? 'Auto-assign' : names.join(', '),
                style: TextStyle(
                  fontSize: 14,
                  color: names.isEmpty ? AppColors.textTertiary : AppColors.textPrimary,
                ),
                textAlign: TextAlign.right,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 6),
            Icon(Icons.chevron_right, size: 16, color: AppColors.textTertiary),
          ],
        ),
      ),
    );
  }
}
