import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:pdf/pdf.dart';
import '../../../../models/employee.dart';
import '../../../../models/workorder_report.dart';
import '../../../../services/pdf/work_order_pdf_service.dart';
import '../../../../theme/app_theme.dart';

class WorkOrderReportScreen extends StatefulWidget {
  const WorkOrderReportScreen({super.key});

  @override
  State<WorkOrderReportScreen> createState() => _WorkOrderReportScreenState();
}

class _WorkOrderReportScreenState extends State<WorkOrderReportScreen> {
  DateTime? _startDate;
  DateTime? _endDate;
  String? _employeeId;
  List<Employee> _employees = [];
  List<WorkOrderReport> _results = [];
  bool _loading = false;
  bool _employeesLoading = true;

  @override
  void initState() {
    super.initState();
    _loadEmployees();
  }

  // ── Data ──────────────────────────────────────────────────

  Future<void> _loadEmployees() async {
    try {
      final data = await Supabase.instance.client
          .from('employees')
          .select('id, full_name, shift_type, active, profile_id')
          .eq('active', true)
          .order('full_name');
      setState(() {
        _employees = (data as List).map((e) => Employee.fromJson(e)).toList();
        _employeesLoading = false;
      });
    } catch (e) {
      setState(() => _employeesLoading = false);
      debugPrint('Employee load error: $e');
    }
  }

  Future<void> _generateReport() async {
    if (_employeeId == null || _startDate == null || _endDate == null) {
      _showSnack('Please select employee and date range');
      return;
    }
    setState(() { _loading = true; _results = []; });
    try {
      final data = await Supabase.instance.client.rpc(
        'get_closed_work_orders_report',
        params: {
          'emp_id': _employeeId,
          'start_date': _startDate!.toIso8601String(),
          'end_date': _endDate!.toIso8601String(),
        },
      );
      setState(() {
        _results = (data as List).map((e) => WorkOrderReport.fromJson(e)).toList();
      });
    } catch (e) {
      _showSnack('Failed to load report');
      debugPrint('Report error: $e');
    }
    setState(() => _loading = false);
  }

  Future<void> _exportPdf() async {
    final themeColor = Theme.of(context).colorScheme.primary;
    await WorkOrderPdfService.exportReport(
      employeeName: _selectedEmployeeName,
      startDate: _startDate!,
      endDate: _endDate!,
      results: _results,
      primaryColor: PdfColor(
        themeColor.red / 255,
        themeColor.green / 255,
        themeColor.blue / 255,
      ),
    );
  }

  // ── Helpers ───────────────────────────────────────────────

  String get _selectedEmployeeName {
    return _employees
        .firstWhere((e) => e.id == _employeeId,
            orElse: () => const Employee(id: '', fullName: '', shiftType: '', active: false))
        .fullName;
  }

  String _formatDate(DateTime d) =>
      '${d.day} ${_monthName(d.month)} ${d.year}';

  String _monthName(int m) => const [
        '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
      ][m];

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));
  }

  Future<void> _pickDate({required bool isStart}) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: Theme.of(context).colorScheme.copyWith(
            primary: AppColors.textPrimary,
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null) {
      setState(() {
        if (isStart) _startDate = picked; else _endDate = picked;
      });
    }
  }

  // ── Build ─────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgPrimary,
      appBar: AppBar(
        backgroundColor: AppColors.bgSurface,
        title: const Text('Work order reports'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(0.5),
          child: Container(height: 0.5, color: AppColors.border),
        ),
      ),
      body: Column(
        children: [

          // ── Filters panel ─────────────────────────────────
          Container(
            color: AppColors.bgSurface,
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [

                // Employee dropdown
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

                // Date row
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const _FieldLabel('Start date'),
                          const SizedBox(height: 5),
                          _DateButton(
                            label: _startDate != null
                                ? _formatDate(_startDate!)
                                : 'Pick date',
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
                            label: _endDate != null
                                ? _formatDate(_endDate!)
                                : 'Pick date',
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
                    onPressed: _loading ? null : _generateReport,
                    child: _loading
                        ? const SizedBox(
                            width: 16, height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Text('Generate report'),
                  ),
                ),
              ],
            ),
          ),

          const Divider(height: 0, thickness: 0.5, color: AppColors.border),

          // ── Results area ──────────────────────────────────
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: AppColors.accent, strokeWidth: 2))
                : _results.isEmpty
                    ? _EmptyState(hasFilters: _employeeId != null)
                    : _ResultsView(
                        results: _results,
                        employeeName: _selectedEmployeeName,
                        startDate: _startDate!,
                        endDate: _endDate!,
                        formatDate: _formatDate,
                        onExport: _exportPdf,
                      ),
          ),
        ],
      ),
    );
  }
}

// ─── Results view ─────────────────────────────────────────────────────────────

class _ResultsView extends StatefulWidget {
  final List<WorkOrderReport> results;
  final String employeeName;
  final DateTime startDate;
  final DateTime endDate;
  final String Function(DateTime) formatDate;
  final VoidCallback onExport;

  const _ResultsView({
    required this.results,
    required this.employeeName,
    required this.startDate,
    required this.endDate,
    required this.formatDate,
    required this.onExport,
  });

  @override
  State<_ResultsView> createState() => _ResultsViewState();
}

class _ResultsViewState extends State<_ResultsView> {
  final Set<int> _expanded = {};

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [

        // ── Compact summary bar ───────────────────────────
        Container(
          color: AppColors.bgSurface,
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
          child: Row(
            children: [
              // Left: name + date range
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.employeeName,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${widget.formatDate(widget.startDate)} – ${widget.formatDate(widget.endDate)}',
                      style: const TextStyle(fontSize: 11, color: AppColors.textTertiary),
                    ),
                  ],
                ),
              ),

              // Total pill
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: AppColors.bgSurface2,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppColors.border2, width: 0.5),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${widget.results.length}',
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Text(
                      'closed',
                      style: TextStyle(fontSize: 10, color: AppColors.textTertiary),
                    ),
                  ],
                ),
              ),

              const SizedBox(width: 8),

              // Export button
              GestureDetector(
                onTap: widget.onExport,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                  decoration: BoxDecoration(
                    color: AppColors.bgSurface,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.border2, width: 0.5),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.picture_as_pdf_outlined, size: 14, color: AppColors.textSecondary),
                      SizedBox(width: 5),
                      Text('PDF', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: AppColors.textSecondary)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),

        const Divider(height: 0, thickness: 0.5, color: AppColors.border),

        // ── Table ─────────────────────────────────────────
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 24),
            children: [

              // Table container
              Container(
                decoration: BoxDecoration(
                  color: AppColors.bgSurface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.border, width: 0.5),
                ),
                child: Column(
                  children: [

                    // Header row
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: const BoxDecoration(
                        color: AppColors.bgSurface2,
                        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
                      ),
                      child: const Row(
                        children: [
                          Expanded(child: _ColHeader('Title')),
                          SizedBox(width: 8),
                          SizedBox(width: 110, child: _ColHeader('Location')),
                          SizedBox(width: 8),
                          SizedBox(width: 70, child: _ColHeader('Closed')),
                        ],
                      ),
                    ),

                    const Divider(height: 0, thickness: 0.5, color: AppColors.border),

                    // Data rows
                    ...widget.results.asMap().entries.map((entry) {
                      final i = entry.key;
                      final item = entry.value;
                      final isExpanded = _expanded.contains(i);
                      final isLast = i == widget.results.length - 1;

                      return Column(
                        children: [
                          GestureDetector(
                            onTap: () => setState(() {
                              if (isExpanded) _expanded.remove(i); else _expanded.add(i);
                            }),
                            behavior: HitTestBehavior.opaque,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: Text(
                                      item.title,
                                      style: const TextStyle(fontSize: 12, color: AppColors.textPrimary, height: 1.4),
                                      maxLines: isExpanded ? null : 1,
                                      overflow: isExpanded ? TextOverflow.visible : TextOverflow.ellipsis,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  SizedBox(
                                    width: 110,
                                    child: Text(
                                      item.location,
                                      style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  SizedBox(
                                    width: 70,
                                    child: Text(
                                      item.modifiedDate.toString().split(' ')[0],
                                      style: const TextStyle(fontSize: 12, color: AppColors.textTertiary),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          if (!isLast)
                            const Divider(height: 0, thickness: 0.5, color: AppColors.border, indent: 12, endIndent: 12),
                        ],
                      );
                    }),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ─── Small helper widgets ─────────────────────────────────────────────────────

class _FieldLabel extends StatelessWidget {
  final String text;
  const _FieldLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: AppColors.textSecondary),
    );
  }
}

class _ColHeader extends StatelessWidget {
  final String text;
  const _ColHeader(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w500, color: AppColors.textTertiary, letterSpacing: 0.04),
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
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
        decoration: BoxDecoration(
          color: AppColors.bgSurface2,
          borderRadius: BorderRadius.circular(9),
          border: Border.all(color: AppColors.border2, width: 0.5),
        ),
        child: Row(
          children: [
            const Icon(Icons.calendar_today_outlined, size: 13, color: AppColors.textTertiary),
            const SizedBox(width: 7),
            Text(label, style: const TextStyle(fontSize: 12, color: AppColors.textPrimary)),
          ],
        ),
      ),
    );
  }
}

class _EmployeeDropdown extends StatelessWidget {
  final List<Employee> employees;
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
      padding: const EdgeInsets.symmetric(horizontal: 11),
      decoration: BoxDecoration(
        color: AppColors.bgSurface2,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: AppColors.border2, width: 0.5),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          isExpanded: true,
          hint: const Text('Select employee', style: TextStyle(fontSize: 13, color: AppColors.textTertiary)),
          style: const TextStyle(fontSize: 13, color: AppColors.textPrimary),
          icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 18, color: AppColors.textTertiary),
          dropdownColor: AppColors.bgSurface,
          borderRadius: BorderRadius.circular(10),
          items: employees.map((emp) => DropdownMenuItem(
            value: emp.id,
            child: Text(emp.fullName, style: const TextStyle(fontSize: 13, color: AppColors.textPrimary)),
          )).toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }
}

class _LoadingInput extends StatelessWidget {
  const _LoadingInput();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 42,
      decoration: BoxDecoration(
        color: AppColors.bgSurface2,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: AppColors.border2, width: 0.5),
      ),
      child: const Center(
        child: SizedBox(
          width: 16, height: 16,
          child: CircularProgressIndicator(strokeWidth: 1.5, color: AppColors.textTertiary),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final bool hasFilters;
  const _EmptyState({required this.hasFilters});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            hasFilters ? Icons.assignment_outlined : Icons.bar_chart_outlined,
            size: 44,
            color: AppColors.bgSurface3,
          ),
          const SizedBox(height: 12),
          Text(
            hasFilters ? 'No closed work orders found' : 'Select filters and generate a report',
            style: const TextStyle(fontSize: 13, color: AppColors.textTertiary),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
