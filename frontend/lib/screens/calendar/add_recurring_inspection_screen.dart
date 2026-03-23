import 'package:flutter/material.dart';
import '../../models/recurring_inspection.dart';
import '../../models/department.dart';
import '../../models/user.dart';
import '../../services/recurring_inspection_service.dart';
import '../../services/department_service.dart';
import '../../services/user_service.dart';
import '../../widgets/technician_selector.dart';
import '../../theme/app_theme.dart';

enum _RepeatOption { never, everyDay, everyWeek, every2Weeks, everyMonth, everyYear, custom }

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
  final _service          = RecurringInspectionService();
  final _departmentService = DepartmentService();
  final _userService       = UserService();

  final _titleCtrl    = TextEditingController();
  final _descCtrl     = TextEditingController();
  final _locationCtrl = TextEditingController();

  List<Department> _departments   = [];
  List<AppUser>    _technicians   = [];
  List<String>     _selectedTechIds = [];
  String _selectedDeptId = '';

  DateTime  _date    = DateTime.now();
  DateTime? _endDate;
  _RepeatOption _repeat          = _RepeatOption.never;
  String        _customFrequency = 'daily';
  int           _customInterval  = 1;
  bool          _isActive        = true;

  bool _saving      = false;
  bool _deleting    = false;
  bool _loadingData = true;

  bool get _isEditing => widget.existing != null;

  // ── Init ────────────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    if (_isEditing) {
      final e = widget.existing!;
      _titleCtrl.text    = e.title;
      _descCtrl.text     = e.description;
      _locationCtrl.text = e.location;
      _selectedDeptId    = e.departmentId;
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
        _departments  = depts;
        _technicians  = techs.where((u) => u.userType == UserType.technician).toList();
        if (_selectedDeptId.isEmpty && depts.isNotEmpty) _selectedDeptId = depts.first.id;
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
    super.dispose();
  }

  // ── Derived params ───────────────────────────────────────────────────────────

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

  // ── Labels ───────────────────────────────────────────────────────────────────

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

  // ── Helpers ──────────────────────────────────────────────────────────────────

  String _formatDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  String _displayDate(DateTime d) {
    const mo = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    return '${mo[d.month - 1]} ${d.day}, ${d.year}';
  }

  // ── Actions ──────────────────────────────────────────────────────────────────

  Future<void> _save() async {
    if (_titleCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Title is required'),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
      ));
      return;
    }
    if (_selectedDeptId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Department is required'),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
      ));
      return;
    }

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
          assignedFixerIds: _selectedTechIds,
        );
      }
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Error: $e'),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
      ));
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
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Error: $e'),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
      ));
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

  void _openRepeatSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _RepeatSheet(
        current: _repeat,
        onSelected: (option) {
          Navigator.pop(context);
          if (option == _RepeatOption.custom) {
            setState(() => _repeat = _RepeatOption.custom);
            WidgetsBinding.instance.addPostFrameCallback((_) => _openCustomSheet());
          } else {
            setState(() {
              _repeat = option;
              if (option == _RepeatOption.never) _endDate = null;
            });
          }
        },
      ),
    );
  }

  void _openCustomSheet() {
    String sheetFreq     = _customFrequency;
    int    sheetInterval = _customInterval;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) {
          final unitLabel = {
            'daily':   sheetInterval == 1 ? 'day'   : 'days',
            'weekly':  sheetInterval == 1 ? 'week'  : 'weeks',
            'monthly': sheetInterval == 1 ? 'month' : 'months',
            'yearly':  sheetInterval == 1 ? 'year'  : 'years',
          }[sheetFreq] ?? '';

          return Container(
            decoration: BoxDecoration(
              color: AppColors.bgSurface,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            ),
            padding: EdgeInsets.only(
              left: 20, right: 20, top: 16,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 36, height: 4,
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: AppColors.border2,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Text('Custom Repeat',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                const SizedBox(height: 20),

                // Frequency pills
                Text('Frequency',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
                const SizedBox(height: 8),
                Row(
                  children: ['daily', 'weekly', 'monthly', 'yearly'].asMap().entries.map((e) {
                    final f   = e.value;
                    final sel = sheetFreq == f;
                    final lbl = f[0].toUpperCase() + f.substring(1);
                    return Expanded(
                      child: Padding(
                        padding: EdgeInsets.only(right: e.key < 3 ? 6 : 0),
                        child: GestureDetector(
                          onTap: () => setSheet(() => sheetFreq = f),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 9),
                            decoration: BoxDecoration(
                              color: sel ? AppColors.accent : AppColors.bgPrimary,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: sel ? AppColors.accent : AppColors.border,
                                width: sel ? 1.5 : 0.5,
                              ),
                            ),
                            child: Center(
                              child: Text(lbl,
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
                const SizedBox(height: 20),

                // Every stepper
                Text('Every',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    _stepBtn(Icons.remove, () => setSheet(() { if (sheetInterval > 1) sheetInterval--; })),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          color: AppColors.bgPrimary,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: AppColors.border, width: 0.5),
                        ),
                        child: Center(
                          child: Text('$sheetInterval',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    _stepBtn(Icons.add, () => setSheet(() { if (sheetInterval < 99) sheetInterval++; })),
                    const SizedBox(width: 12),
                    Text(unitLabel, style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
                  ],
                ),
                const SizedBox(height: 24),

                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () {
                      setState(() { _customFrequency = sheetFreq; _customInterval = sheetInterval; });
                      Navigator.pop(ctx);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.accent,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      elevation: 0,
                    ),
                    child: const Text('Done', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _stepBtn(IconData icon, VoidCallback onTap) => GestureDetector(
    onTap: onTap,
    child: Container(
      width: 44, height: 44,
      decoration: BoxDecoration(
        color: AppColors.bgPrimary,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border, width: 0.5),
      ),
      child: Icon(icon, size: 18, color: AppColors.textPrimary),
    ),
  );

  void _openTechSelector() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => TechnicianSelector(
        technicians: _technicians,
        selectedIds: _selectedTechIds,
        onChanged: (ids) {
          setState(() => _selectedTechIds = ids);
          Navigator.pop(context);
        },
      ),
    );
  }

  void _showDepartmentPicker() {
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
                setState(() => _selectedDeptId = d.id);
                Navigator.pop(ctx);
              },
              child: Container(
                height: 50,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    Text(d.name, style: TextStyle(fontSize: 15, color: AppColors.textPrimary)),
                    const Spacer(),
                    if (_selectedDeptId == d.id)
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

  // ── Build ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgPrimary,
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Container(
              color: AppColors.bgSurface,
              padding: const EdgeInsets.fromLTRB(8, 12, 8, 12),
              child: Row(
                children: [
                  IconButton(
                    icon: Icon(Icons.arrow_back_ios_new_rounded, size: 18, color: AppColors.textPrimary),
                    onPressed: () => Navigator.pop(context),
                  ),
                  Expanded(
                    child: Text(
                      _isEditing ? 'Edit Inspection' : 'New Inspection',
                      style: TextStyle(
                        fontSize: 17, fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary, letterSpacing: -0.3,
                      ),
                    ),
                  ),
                  if (_isEditing)
                    IconButton(
                      icon: Icon(Icons.delete_outline_rounded, size: 20, color: Colors.red.shade400),
                      onPressed: _deleting ? null : _delete,
                    ),
                ],
              ),
            ),
            Divider(height: 0, thickness: 0.5, color: AppColors.border),

            Expanded(
              child: _loadingData
                  ? const Center(child: CircularProgressIndicator())
                  : SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [

                          // ── Group 1: Title / Description / Location ──────────
                          _group([
                            // Large title field
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
                            _inlineTextField(_descCtrl,     'Description', 'Add description', maxLines: 3),
                            _divider(),
                            _inlineTextField(_locationCtrl, 'Location',    'Add location'),
                          ]),

                          const SizedBox(height: 8),

                          // ── Group 2: Date / Repeat / End Repeat ─────────────
                          _group([
                            _tapRow(
                              label: 'Date',
                              value: _displayDate(_date),
                              valueColor: AppColors.accent,
                              onTap: _pickDate,
                            ),
                            _divider(),
                            _tapRow(
                              label: 'Repeat',
                              value: _repeatLabel,
                              onTap: _openRepeatSheet,
                            ),
                            if (_repeat != _RepeatOption.never) ...[
                              _divider(),
                              _endRepeatRow(),
                            ],
                          ]),

                          const SizedBox(height: 8),

                          // ── Group 3: Department ─────────────────────────────
                          _group([
                            _tapRow(
                              label: 'Department',
                              value: _departments.where((d) => d.id == _selectedDeptId).firstOrNull?.name ?? 'Select',
                              valueColor: _selectedDeptId.isEmpty ? AppColors.textTertiary : null,
                              onTap: _showDepartmentPicker,
                            ),
                          ]),

                          const SizedBox(height: 8),

                          // ── Group 4: Technicians ────────────────────────────
                          _group([
                            _techRow(),
                          ]),

                          if (_isEditing) ...[
                            const SizedBox(height: 8),
                            // ── Group 5: Active ─────────────────────────────
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

                          const SizedBox(height: 24),

                          SizedBox(
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
                                  ? const SizedBox(width: 20, height: 20,
                                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                  : Text(_isEditing ? 'Update' : 'Create',
                                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                            ),
                          ),
                          const SizedBox(height: 16),
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Row / Group helpers ──────────────────────────────────────────────────────

  Widget _group(List<Widget> rows) => Container(
    decoration: BoxDecoration(
      color: AppColors.bgSurface,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: AppColors.border, width: 0.5),
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
  }) {
    return InkWell(
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 52),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
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

  // End Repeat row: separate tap targets for date text and clear [x]
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

  Widget _techRow() {
    final names = _selectedTechIds
        .map((id) => _technicians.where((t) => t.id == id).firstOrNull?.fullName ?? id)
        .toList();
    return InkWell(
      onTap: _openTechSelector,
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

// ── Repeat picker bottom sheet ──────────────────────────────────────────────────

class _RepeatSheet extends StatelessWidget {
  final _RepeatOption current;
  final void Function(_RepeatOption) onSelected;

  const _RepeatSheet({required this.current, required this.onSelected});

  static const _options = [
    (_RepeatOption.never,       'Does not repeat'),
    (_RepeatOption.everyDay,    'Every day'),
    (_RepeatOption.everyWeek,   'Every week'),
    (_RepeatOption.every2Weeks, 'Every 2 weeks'),
    (_RepeatOption.everyMonth,  'Every month'),
    (_RepeatOption.everyYear,   'Every year'),
    (_RepeatOption.custom,      'Custom…'),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
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
              child: Text('Repeat',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
            ),
          ),
          ..._options.map((item) {
            final (option, label) = item;
            final selected = current == option;
            return InkWell(
              onTap: () => onSelected(option),
              child: Container(
                height: 50,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    Text(label, style: TextStyle(fontSize: 15, color: AppColors.textPrimary)),
                    const Spacer(),
                    if (selected)
                      Icon(Icons.check_rounded, size: 18, color: AppColors.accent),
                  ],
                ),
              ),
            );
          }),
        ],
      ),
    );
  }
}
