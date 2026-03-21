import 'package:flutter/material.dart';
import '../../models/user.dart';
import '../../models/workorder_report.dart';
import '../../services/user_service.dart';
import '../../services/report_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/pdf_preview_screen.dart';

class MonthlyTaskReportScreen extends StatefulWidget {
  const MonthlyTaskReportScreen({super.key});

  @override
  State<MonthlyTaskReportScreen> createState() =>
      _MonthlyTaskReportScreenState();
}

class _MonthlyTaskReportScreenState extends State<MonthlyTaskReportScreen> {
  // ── Form state ──────────────────────────────────────────────────────────────
  DateTime? _startDate;
  DateTime? _endDate;
  String? _employeeId;

  List<AppUser> _employees    = [];
  bool _employeesLoading      = true;
  bool _loading               = false;

  @override
  void initState() {
    super.initState();
    _loadEmployees();
  }

  // ── Data ────────────────────────────────────────────────────────────────────

  Future<void> _loadEmployees() async {
    try {
      final employees = await UserService().fetchTechnicians();
      setState(() {
        _employees       = employees;
        _employeesLoading = false;
      });
    } catch (e) {
      setState(() => _employeesLoading = false);
      debugPrint('Employee load error: $e');
    }
  }

  String _formatDate(DateTime d) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${d.day.toString().padLeft(2, '0')} ${months[d.month - 1]} ${d.year}';
  }

  Future<void> _pickDate({required bool isStart}) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: isStart
          ? (_startDate ?? DateTime.now())
          : (_endDate ?? DateTime.now()),
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      builder: (context, child) => Theme(
        data: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.light(
            primary: AppColors.accent,
            onPrimary: Colors.white,
            surface: AppColors.bgSurface,
            onSurface: AppColors.textPrimary,
            secondaryContainer: AppColors.accentBg,
            onSecondaryContainer: AppColors.accent,
            outline: AppColors.border2,
          ),
          textButtonTheme: TextButtonThemeData(
            style: TextButton.styleFrom(
              foregroundColor: AppColors.accent,
              textStyle:
                  const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
            ),
          ),
          dialogTheme: DialogThemeData(
            backgroundColor: AppColors.bgSurface,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            elevation: 4,
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null) {
      setState(() {
        if (isStart) {
          _startDate = picked;
        } else {
          _endDate = picked;
        }
      });
    }
  }

  Future<void> _generate() async {
    if (_employeeId == null) {
      _showSnack('Please select an employee');
      return;
    }
    if (_startDate == null || _endDate == null) {
      _showSnack('Please select a start and end date');
      return;
    }
    if (_endDate!.isBefore(_startDate!)) {
      _showSnack('End date must be after start date');
      return;
    }
    setState(() => _loading = true);
    try {
      final List<WorkOrderReport> results = await ReportService().getClosedWorkOrders(
        technicianId: _employeeId!,
        startDate:    _startDate!,
        endDate:      _endDate!,
      );

      if (results.isEmpty) {
        _showSnack('No closed work orders found for this period');
        setState(() => _loading = false);
        return;
      }

      final employee = _employees.firstWhere((e) => e.id == _employeeId);
      final name     = employee.fullName ?? employee.email;

      // Convert WorkOrderReport → task map for the PDF endpoint
      final tasks = results.map((r) {
        final d = r.modifiedDate;
        final day   = d.day.toString().padLeft(2, '0');
        final month = d.month.toString().padLeft(2, '0');
        return {
          'description': r.title,
          'date':        '$day/$month/${d.year}',
          'location':    r.location,
        };
      }).toList();

      final bytes = await ReportService().generateMonthlyTasksReport(
        name:      name,
        startDate: _formatDate(_startDate!),
        endDate:   _formatDate(_endDate!),
        tasks:     tasks,
      );

      if (!mounted) return;

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => PdfPreviewScreen(
            title: 'Monthly Report – ${_formatDate(_startDate!)} to ${_formatDate(_endDate!)}',
            buildPdf: () async => bytes,
          ),
        ),
      );
    } catch (e) {
      if (mounted) _showSnack('Failed to generate report: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));
  }

  // ── Build ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgPrimary,
      appBar: AppBar(
        backgroundColor: AppColors.bgSurface,
        leading: GestureDetector(
          onTap: () => Navigator.pop(context),
          child: Center(
            child: Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: AppColors.bgSurface2,
                borderRadius: BorderRadius.circular(9),
                border: Border.all(color: AppColors.border2, width: 0.5),
              ),
              child: Icon(Icons.arrow_back_rounded,
                  size: 16, color: AppColors.textSecondary),
            ),
          ),
        ),
        title: const Text('Monthly task report'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(0.5),
          child: Container(height: 0.5, color: AppColors.border),
        ),
      ),
      body: Column(
        children: [
          // ── Filters panel ──────────────────────────────────────────────────
          Container(
            color: AppColors.bgSurface,
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Employee
                const _FieldLabel('Employee'),
                const SizedBox(height: 5),
                _employeesLoading
                    ? const _LoadingInput()
                    : _EmployeeDropdown(
                        employees: _employees,
                        value: _employeeId,
                        onChanged: (v) => setState(() => _employeeId = v),
                      ),

                const SizedBox(height: 10),

                // Start date + End date row
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const _FieldLabel('Start date'),
                          const SizedBox(height: 5),
                          _DateButton(
                            label: _startDate == null
                                ? 'Start date'
                                : _formatDate(_startDate!),
                            onTap: () => _pickDate(isStart: true),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const _FieldLabel('End date'),
                          const SizedBox(height: 5),
                          _DateButton(
                            label: _endDate == null
                                ? 'End date'
                                : _formatDate(_endDate!),
                            onTap: () => _pickDate(isStart: false),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 12),

                // Generate button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _loading ? null : _generate,
                    child: _loading
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        : const Text('Generate report'),
                  ),
                ),
              ],
            ),
          ),

          Divider(height: 0, thickness: 0.5, color: AppColors.border),

          // ── Info area ──────────────────────────────────────────────────────
          Expanded(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.assignment_outlined,
                      size: 44, color: AppColors.bgSurface3),
                  const SizedBox(height: 12),
                  Text(
                    _employeeId == null || _startDate == null || _endDate == null
                        ? 'Select an employee and date range\nto generate a monthly tasks report'
                        : 'Tap "Generate report" to fetch closed work\norders from ${_formatDate(_startDate!)} to ${_formatDate(_endDate!)}',
                    style: TextStyle(
                        fontSize: 13, color: AppColors.textTertiary),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Helper widgets ─────────────────────────────────────────────────────────────

class _FieldLabel extends StatelessWidget {
  final String text;
  const _FieldLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w500,
          color: AppColors.textSecondary),
    );
  }
}

class _LoadingInput extends StatelessWidget {
  const _LoadingInput();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 38,
      decoration: BoxDecoration(
        color: AppColors.bgSurface2,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: AppColors.border2, width: 0.5),
      ),
      child: Center(
        child: SizedBox(
          width: 14,
          height: 14,
          child: CircularProgressIndicator(
              strokeWidth: 1.5, color: AppColors.textTertiary),
        ),
      ),
    );
  }
}

class _EmployeeDropdown extends StatelessWidget {
  final List<AppUser> employees;
  final String? value;
  final ValueChanged<String?> onChanged;

  const _EmployeeDropdown({
    required this.employees,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 1),
      decoration: BoxDecoration(
        color: AppColors.bgSurface2,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: AppColors.border2, width: 0.5),
      ),
      child: DropdownButton<String>(
        value: value,
        isExpanded: true,
        underline: const SizedBox(),
        hint: Text('Select employee',
            style: TextStyle(fontSize: 13, color: AppColors.textTertiary)),
        style: TextStyle(fontSize: 13, color: AppColors.textPrimary),
        dropdownColor: AppColors.bgSurface,
        borderRadius: BorderRadius.circular(10),
        items: employees
            .map((e) => DropdownMenuItem(
                  value: e.id,
                  child: Text(e.fullName ?? e.email),
                ))
            .toList(),
        onChanged: onChanged,
      ),
    );
  }
}

class _DateButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _DateButton({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 38,
        padding: const EdgeInsets.symmetric(horizontal: 11),
        decoration: BoxDecoration(
          color: AppColors.bgSurface2,
          borderRadius: BorderRadius.circular(9),
          border: Border.all(color: AppColors.border2, width: 0.5),
        ),
        child: Row(
          children: [
            Icon(Icons.calendar_today_outlined,
                size: 14, color: AppColors.textTertiary),
            const SizedBox(width: 7),
            Expanded(
              child: Text(
                label,
                style: TextStyle(fontSize: 13, color: AppColors.textPrimary),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
