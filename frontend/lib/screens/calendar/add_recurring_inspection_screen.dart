import 'package:flutter/material.dart';
import '../../models/recurring_inspection.dart';
import '../../models/department.dart';
import '../../models/user.dart';
import '../../services/recurring_inspection_service.dart';
import '../../services/department_service.dart';
import '../../services/user_service.dart';
import '../../widgets/technician_selector.dart';
import '../../theme/app_theme.dart';

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
  final _service = RecurringInspectionService();
  final _departmentService = DepartmentService();
  final _userService = UserService();
  final _formKey = GlobalKey<FormState>();

  final _titleCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _locationCtrl = TextEditingController();

  List<Department> _departments = [];
  List<AppUser> _technicians = [];
  List<String> _selectedTechIds = [];

  String _selectedDeptId = '';
  String _frequency = 'weekly';
  int _dayOfWeek = 0; // Mon
  int _dayOfMonth = 1;
  DateTime _startDate = DateTime.now();
  DateTime? _endDate;
  bool _isActive = true;

  bool _saving = false;
  bool _deleting = false;
  bool _loadingData = true;

  bool get _isEditing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    if (_isEditing) {
      final e = widget.existing!;
      _titleCtrl.text = e.title;
      _descCtrl.text = e.description;
      _locationCtrl.text = e.location;
      _selectedDeptId = e.departmentId;
      _frequency = e.frequency;
      _dayOfWeek = e.dayOfWeek ?? 0;
      _dayOfMonth = e.dayOfMonth ?? 1;
      _startDate = DateTime.tryParse(e.startDate) ?? DateTime.now();
      _endDate = e.endDate != null ? DateTime.tryParse(e.endDate!) : null;
      _isActive = e.isActive;
      _selectedTechIds = e.assignees.map((a) => a.id).toList();
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
        if (_selectedDeptId.isEmpty && depts.isNotEmpty) {
          _selectedDeptId = depts.first.id;
        }
        _loadingData = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadingData = false);
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

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
          dayOfWeek: _frequency == 'weekly' ? _dayOfWeek : null,
          dayOfMonth: _frequency == 'monthly' ? _dayOfMonth : null,
          startDate: _formatDate(_startDate),
          endDate: _endDate != null ? _formatDate(_endDate!) : null,
          isActive: _isActive,
          assignedFixerIds: _selectedTechIds,
        );
      } else {
        await _service.create(
          title: _titleCtrl.text.trim(),
          description: _descCtrl.text.trim(),
          location: _locationCtrl.text.trim(),
          departmentId: _selectedDeptId,
          frequency: _frequency,
          dayOfWeek: _frequency == 'weekly' ? _dayOfWeek : null,
          dayOfMonth: _frequency == 'monthly' ? _dayOfMonth : null,
          startDate: _formatDate(_startDate),
          endDate: _endDate != null ? _formatDate(_endDate!) : null,
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
        behavior: SnackBarBehavior.floating,
        backgroundColor: Colors.red,
      ));
    }
  }

  Future<void> _delete() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Recurring Inspection'),
        content: const Text('This will stop future auto-generated inspections. Continue?'),
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
        behavior: SnackBarBehavior.floating,
        backgroundColor: Colors.red,
      ));
    }
  }

  String _formatDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _pickDate(bool isStart) async {
    final initial = isStart ? _startDate : (_endDate ?? DateTime.now());
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2024),
      lastDate: DateTime(2030),
    );
    if (picked == null) return;
    setState(() {
      if (isStart) {
        _startDate = picked;
      } else {
        _endDate = picked;
      }
    });
  }

  void _openTechSelector() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => TechnicianSelector(
        technicians: _technicians,
        selectedIds: _selectedTechIds,
        onChanged: (ids) {
          setState(() => _selectedTechIds = ids);
          Navigator.pop(context);
        },
      ),
    );
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    _locationCtrl.dispose();
    super.dispose();
  }

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
                      _isEditing ? 'Edit Recurring Inspection' : 'New Recurring Inspection',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                        letterSpacing: -0.3,
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

            // Form
            Expanded(
              child: _loadingData
                  ? const Center(child: CircularProgressIndicator())
                  : SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: Form(
                        key: _formKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Title
                            _buildLabel('Title'),
                            const SizedBox(height: 6),
                            _buildTextField(_titleCtrl, 'e.g. Fire extinguisher check', validator: (v) {
                              if (v == null || v.trim().isEmpty) return 'Title is required';
                              return null;
                            }),

                            const SizedBox(height: 16),

                            // Description
                            _buildLabel('Description'),
                            const SizedBox(height: 6),
                            _buildTextField(_descCtrl, 'Optional details...', maxLines: 3),

                            const SizedBox(height: 16),

                            // Location
                            _buildLabel('Location'),
                            const SizedBox(height: 6),
                            _buildTextField(_locationCtrl, 'e.g. Building A, Floor 2'),

                            const SizedBox(height: 16),

                            // Department
                            _buildLabel('Department'),
                            const SizedBox(height: 6),
                            _buildDropdown(),

                            const SizedBox(height: 16),

                            // Frequency
                            _buildLabel('Frequency'),
                            const SizedBox(height: 6),
                            _buildFrequencySelector(),

                            const SizedBox(height: 16),

                            // Day selector based on frequency
                            if (_frequency == 'weekly') ...[
                              _buildLabel('Day of Week'),
                              const SizedBox(height: 6),
                              _buildDayOfWeekSelector(),
                              const SizedBox(height: 16),
                            ],
                            if (_frequency == 'monthly') ...[
                              _buildLabel('Day of Month'),
                              const SizedBox(height: 6),
                              _buildDayOfMonthSelector(),
                              const SizedBox(height: 16),
                            ],

                            // Date range
                            Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      _buildLabel('Start Date'),
                                      const SizedBox(height: 6),
                                      _buildDateButton(_startDate, () => _pickDate(true)),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      _buildLabel('End Date (optional)'),
                                      const SizedBox(height: 6),
                                      _buildDateButton(_endDate, () => _pickDate(false), placeholder: 'No end date'),
                                    ],
                                  ),
                                ),
                              ],
                            ),

                            const SizedBox(height: 16),

                            // Assigned technicians
                            _buildLabel('Assigned Technicians'),
                            const SizedBox(height: 6),
                            GestureDetector(
                              onTap: _openTechSelector,
                              child: Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: AppColors.bgSurface,
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: AppColors.border, width: 0.5),
                                ),
                                child: _selectedTechIds.isEmpty
                                    ? Text(
                                        'Auto-assign from department',
                                        style: TextStyle(fontSize: 13, color: AppColors.textTertiary),
                                      )
                                    : Wrap(
                                        spacing: 6,
                                        runSpacing: 4,
                                        children: _selectedTechIds.map((id) {
                                          final tech = _technicians.where((t) => t.id == id).firstOrNull;
                                          return Chip(
                                            label: Text(tech?.fullName ?? id, style: const TextStyle(fontSize: 11)),
                                            deleteIcon: const Icon(Icons.close, size: 14),
                                            onDeleted: () {
                                              setState(() => _selectedTechIds.remove(id));
                                            },
                                            visualDensity: VisualDensity.compact,
                                            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                          );
                                        }).toList(),
                                      ),
                              ),
                            ),

                            if (_isEditing) ...[
                              const SizedBox(height: 16),
                              Row(
                                children: [
                                  _buildLabel('Active'),
                                  const Spacer(),
                                  Switch.adaptive(
                                    value: _isActive,
                                    onChanged: (v) => setState(() => _isActive = v),
                                    activeColor: AppColors.accent,
                                  ),
                                ],
                              ),
                            ],

                            const SizedBox(height: 32),

                            // Save button
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

                            const SizedBox(height: 16),
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

  Widget _buildLabel(String text) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: AppColors.textSecondary,
      ),
    );
  }

  Widget _buildTextField(
    TextEditingController controller,
    String hint, {
    int maxLines = 1,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      maxLines: maxLines,
      validator: validator,
      style: TextStyle(fontSize: 13, color: AppColors.textPrimary),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(fontSize: 13, color: AppColors.textTertiary),
        filled: true,
        fillColor: AppColors.bgSurface,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: AppColors.border, width: 0.5),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: AppColors.border, width: 0.5),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: AppColors.accent, width: 1),
        ),
      ),
    );
  }

  Widget _buildDropdown() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: AppColors.bgSurface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border, width: 0.5),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _departments.any((d) => d.id == _selectedDeptId) ? _selectedDeptId : null,
          isExpanded: true,
          hint: Text('Select department', style: TextStyle(fontSize: 13, color: AppColors.textTertiary)),
          style: TextStyle(fontSize: 13, color: AppColors.textPrimary),
          items: _departments.map((d) {
            return DropdownMenuItem(value: d.id, child: Text(d.name));
          }).toList(),
          onChanged: (v) {
            if (v != null) setState(() => _selectedDeptId = v);
          },
        ),
      ),
    );
  }

  Widget _buildFrequencySelector() {
    return Row(
      children: ['daily', 'weekly', 'monthly'].map((f) {
        final selected = _frequency == f;
        final label = f[0].toUpperCase() + f.substring(1);
        return Expanded(
          child: Padding(
            padding: EdgeInsets.only(right: f != 'monthly' ? 8 : 0),
            child: GestureDetector(
              onTap: () => setState(() => _frequency = f),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: selected ? AppColors.accent : AppColors.bgSurface,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: selected ? AppColors.accent : AppColors.border,
                    width: selected ? 1.5 : 0.5,
                  ),
                ),
                child: Center(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: selected ? Colors.white : AppColors.textSecondary,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildDayOfWeekSelector() {
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return Wrap(
      spacing: 6,
      children: List.generate(7, (i) {
        final selected = _dayOfWeek == i;
        return GestureDetector(
          onTap: () => setState(() => _dayOfWeek = i),
          child: Container(
            width: 42,
            height: 36,
            decoration: BoxDecoration(
              color: selected ? AppColors.accent : AppColors.bgSurface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: selected ? AppColors.accent : AppColors.border,
                width: selected ? 1.5 : 0.5,
              ),
            ),
            child: Center(
              child: Text(
                days[i],
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: selected ? Colors.white : AppColors.textSecondary,
                ),
              ),
            ),
          ),
        );
      }),
    );
  }

  Widget _buildDayOfMonthSelector() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: AppColors.bgSurface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border, width: 0.5),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<int>(
          value: _dayOfMonth,
          isExpanded: true,
          style: TextStyle(fontSize: 13, color: AppColors.textPrimary),
          items: List.generate(28, (i) {
            final day = i + 1;
            return DropdownMenuItem(value: day, child: Text('Day $day'));
          }),
          onChanged: (v) {
            if (v != null) setState(() => _dayOfMonth = v);
          },
        ),
      ),
    );
  }

  Widget _buildDateButton(DateTime? date, VoidCallback onTap, {String placeholder = ''}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.bgSurface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.border, width: 0.5),
        ),
        child: Row(
          children: [
            Icon(Icons.calendar_today_rounded, size: 14, color: AppColors.textTertiary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                date != null ? _formatDate(date) : placeholder,
                style: TextStyle(
                  fontSize: 13,
                  color: date != null ? AppColors.textPrimary : AppColors.textTertiary,
                ),
              ),
            ),
            if (date != null && placeholder.isNotEmpty)
              GestureDetector(
                onTap: () => setState(() => _endDate = null),
                child: Icon(Icons.close, size: 14, color: AppColors.textTertiary),
              ),
          ],
        ),
      ),
    );
  }
}
