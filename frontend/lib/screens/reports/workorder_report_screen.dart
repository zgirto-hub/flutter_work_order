import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';
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
  WorkOrderPdfTheme _selectedPdfTheme = WorkOrderPdfTheme.copperNight;

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
    setState(() {
      _loading = true;
      _results = [];
    });
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
        _results =
            (data as List).map((e) => WorkOrderReport.fromJson(e)).toList();
      });
    } catch (e) {
      _showSnack('Failed to load report');
      debugPrint('Report error: $e');
    }
    setState(() => _loading = false);
  }

  Future<void> _exportPdf() async {
    final themeColor = Theme.of(context).colorScheme.primary;
    final primaryColor = PdfColor(themeColor.r, themeColor.g, themeColor.b);
    final employeeName = _selectedEmployeeName;
    final startDate = _startDate!;
    final endDate = _endDate!;
    final results = List.of(_results);
    final selectedTheme = await _pickPdfTheme();

    if (selectedTheme == null || !mounted) return;

    setState(() => _selectedPdfTheme = selectedTheme);

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _PdfPreviewScreen(
          title: 'Report – $employeeName',
          buildPdf: () => WorkOrderPdfService.buildReport(
            employeeName: employeeName,
            startDate: startDate,
            endDate: endDate,
            results: results,
            primaryColor: primaryColor,
            theme: selectedTheme,
          ),
        ),
      ),
    );
  }

  Future<WorkOrderPdfTheme?> _pickPdfTheme() {
    return showModalBottomSheet<WorkOrderPdfTheme>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        final options = WorkOrderPdfTheme.values;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: Container(
              decoration: BoxDecoration(
                color: AppColors.bgSurface,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: AppColors.border, width: 0.6),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.14),
                    blurRadius: 26,
                    offset: const Offset(0, 12),
                  ),
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 18),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 44,
                        height: 4,
                        decoration: BoxDecoration(
                          color: AppColors.border2,
                          borderRadius: BorderRadius.circular(99),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Choose PDF theme',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Each version keeps the same report data but changes the visual direction.',
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.45,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 16),
                    ...options.map(
                      (theme) => Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _PdfThemeTile(
                          theme: theme,
                          selected: theme == _selectedPdfTheme,
                          onTap: () => Navigator.pop(context, theme),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  // ── Helpers ───────────────────────────────────────────────

  String get _selectedEmployeeName {
    return _employees
        .firstWhere((e) => e.id == _employeeId,
            orElse: () => const Employee(
                id: '', fullName: '', shiftType: '', active: false))
        .fullName;
  }

  String _formatDate(DateTime d) => '${d.day} ${_monthName(d.month)} ${d.year}';

  String _monthName(int m) => const [
        '',
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

  // ── Build ─────────────────────────────────────────────────

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
        title: Text('Work order reports'),
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
                SizedBox(height: 5),
                _employeesLoading
                    ? const _LoadingInput()
                    : _EmployeeDropdown(
                        employees: _employees,
                        value: _employeeId,
                        onChanged: (v) => setState(() => _employeeId = v),
                      ),

                SizedBox(height: 10),

                // Date row
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const _FieldLabel('Start date'),
                          SizedBox(height: 5),
                          _DateButton(
                            label: _startDate != null
                                ? _formatDate(_startDate!)
                                : 'Pick date',
                            onTap: () => _pickDate(isStart: true),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const _FieldLabel('End date'),
                          SizedBox(height: 5),
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

                SizedBox(height: 12),

                // Generate button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _loading ? null : _generateReport,
                    child: _loading
                        ? SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        : Text('Generate report'),
                  ),
                ),
              ],
            ),
          ),

          Divider(height: 0, thickness: 0.5, color: AppColors.border),

          // ── Results area ──────────────────────────────────
          Expanded(
            child: _loading
                ? Center(
                    child: CircularProgressIndicator(
                        color: AppColors.accent, strokeWidth: 2))
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
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      '${widget.formatDate(widget.startDate)} – ${widget.formatDate(widget.endDate)}',
                      style: TextStyle(
                          fontSize: 11, color: AppColors.textTertiary),
                    ),
                  ],
                ),
              ),

              // Total pill
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
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
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    SizedBox(width: 4),
                    Text(
                      'closed',
                      style: TextStyle(
                          fontSize: 10, color: AppColors.textTertiary),
                    ),
                  ],
                ),
              ),

              SizedBox(width: 8),

              // Export button
              GestureDetector(
                onTap: widget.onExport,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                  decoration: BoxDecoration(
                    color: AppColors.bgSurface,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.border2, width: 0.5),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.picture_as_pdf_outlined,
                          size: 14, color: AppColors.textSecondary),
                      SizedBox(width: 5),
                      Text('PDF',
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: AppColors.textSecondary)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),

        Divider(height: 0, thickness: 0.5, color: AppColors.border),

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
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: AppColors.bgSurface2,
                        borderRadius:
                            BorderRadius.vertical(top: Radius.circular(12)),
                      ),
                      child: Row(
                        children: [
                          Expanded(child: _ColHeader('Title')),
                          SizedBox(width: 8),
                          SizedBox(width: 110, child: _ColHeader('Location')),
                          SizedBox(width: 8),
                          SizedBox(width: 90, child: _ColHeader('Closed')),
                        ],
                      ),
                    ),

                    Divider(height: 0, thickness: 0.5, color: AppColors.border),

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
                              if (isExpanded) {
                                _expanded.remove(i);
                              } else {
                                _expanded.add(i);
                              }
                            }),
                            behavior: HitTestBehavior.opaque,
                            child: AnimatedSize(
                              duration: const Duration(milliseconds: 200),
                              curve: Curves.easeInOutCubic,
                              alignment: Alignment.topCenter,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 9),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(
                                      child: Text(
                                        item.title,
                                        style: TextStyle(
                                            fontSize: 12,
                                            color: AppColors.textPrimary,
                                            height: 1.4),
                                        maxLines: isExpanded ? null : 1,
                                        overflow: isExpanded
                                            ? TextOverflow.visible
                                            : TextOverflow.ellipsis,
                                      ),
                                    ),
                                    SizedBox(width: 8),
                                    SizedBox(
                                      width: 110,
                                      child: Text(
                                        item.location,
                                        style: TextStyle(
                                            fontSize: 12,
                                            color: AppColors.textSecondary),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    SizedBox(width: 8),
                                    SizedBox(
                                      width: 90,
                                      child: Text(
                                        item.modifiedDate
                                            .toString()
                                            .split(' ')[0],
                                        style: TextStyle(
                                            fontSize: 12,
                                            color: AppColors.textTertiary),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          if (!isLast)
                            Divider(
                                height: 0,
                                thickness: 0.5,
                                color: AppColors.border,
                                indent: 12,
                                endIndent: 12),
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
      style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w500,
          color: AppColors.textSecondary),
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
      style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w500,
          color: AppColors.textTertiary,
          letterSpacing: 0.04),
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
            Icon(Icons.calendar_today_outlined,
                size: 13, color: AppColors.textTertiary),
            SizedBox(width: 7),
            Text(label,
                style: TextStyle(fontSize: 12, color: AppColors.textPrimary)),
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
          hint: Text('Select employee',
              style: TextStyle(fontSize: 13, color: AppColors.textTertiary)),
          style: TextStyle(fontSize: 13, color: AppColors.textPrimary),
          icon: Icon(Icons.keyboard_arrow_down_rounded,
              size: 18, color: AppColors.textTertiary),
          dropdownColor: AppColors.bgSurface,
          borderRadius: BorderRadius.circular(10),
          items: employees
              .map((emp) => DropdownMenuItem(
                    value: emp.id,
                    child: Text(emp.fullName,
                        style: TextStyle(
                            fontSize: 13, color: AppColors.textPrimary)),
                  ))
              .toList(),
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
      child: Center(
        child: SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(
              strokeWidth: 1.5, color: AppColors.textTertiary),
        ),
      ),
    );
  }
}

class _PdfThemeTile extends StatelessWidget {
  final WorkOrderPdfTheme theme;
  final bool selected;
  final VoidCallback onTap;

  const _PdfThemeTile({
    required this.theme,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final swatch = _themeSwatch(theme);
    final preview = _themePreview(theme);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Ink(
          decoration: BoxDecoration(
            color: selected ? AppColors.accentBg : AppColors.bgSurface2,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: selected ? AppColors.accent : AppColors.border2,
              width: selected ? 1.0 : 0.6,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 82,
                  height: 108,
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: preview.paper,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: preview.frame, width: 0.8),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.08),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: Stack(
                      children: [
                        Container(color: preview.paper),
                        Container(
                          height: 28,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: swatch.take(2).toList(),
                            ),
                          ),
                        ),
                        Positioned(
                          top: -8,
                          right: -10,
                          child: Container(
                            width: 34,
                            height: 34,
                            decoration: BoxDecoration(
                              color: preview.glow,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                        Positioned(
                          top: 7,
                          left: 8,
                          right: 8,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                width: 18,
                                height: 4,
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.88),
                                  borderRadius: BorderRadius.circular(99),
                                ),
                              ),
                              const SizedBox(height: 5),
                              Container(
                                width: 30,
                                height: 8,
                                decoration: BoxDecoration(
                                  color: preview.heroText,
                                  borderRadius: BorderRadius.circular(99),
                                ),
                              ),
                            ],
                          ),
                        ),
                        Positioned(
                          top: 34,
                          left: 8,
                          right: 8,
                          child: Row(
                            children: [
                              Expanded(
                                child: Container(
                                  height: 24,
                                  decoration: BoxDecoration(
                                    color: preview.cardDark,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 5),
                              Container(
                                width: 18,
                                height: 24,
                                decoration: BoxDecoration(
                                  color: preview.cardAccent,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                            ],
                          ),
                        ),
                        Positioned(
                          left: 8,
                          right: 8,
                          bottom: 10,
                          child: Column(
                            children: [
                              _previewRow(
                                preview.barAccent,
                                preview.lineDark,
                                0.78,
                              ),
                              const SizedBox(height: 5),
                              _previewRow(
                                preview.barAccentMuted,
                                preview.lineSoft,
                                0.58,
                              ),
                              const SizedBox(height: 5),
                              _previewRow(
                                preview.barBase,
                                preview.lineSoft,
                                0.42,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              theme.label,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: AppColors.textPrimary,
                              ),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(colors: swatch),
                              borderRadius: BorderRadius.circular(99),
                            ),
                            child: const Text(
                              'Preview',
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        theme.description,
                        style: TextStyle(
                          fontSize: 11.5,
                          height: 1.35,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          _themeChip('Hero', swatch.first),
                          _themeChip('Metrics', swatch[1]),
                          _themeChip('Ledger', swatch.last),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: selected ? AppColors.accent : Colors.transparent,
                      border: Border.all(
                        color: selected ? AppColors.accent : AppColors.border2,
                        width: 1,
                      ),
                    ),
                    child: selected
                        ? const Icon(Icons.check_rounded,
                            size: 14, color: Colors.white)
                        : null,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _previewRow(Color barColor, Color lineColor, double widthFactor) {
    return Row(
      children: [
        Expanded(
          child: Container(
            height: 6,
            decoration: BoxDecoration(
              color: lineColor,
              borderRadius: BorderRadius.circular(99),
            ),
            child: Align(
              alignment: Alignment.centerLeft,
              child: FractionallySizedBox(
                widthFactor: widthFactor,
                child: Container(
                  decoration: BoxDecoration(
                    color: barColor,
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 6),
        Container(
          width: 10,
          height: 4,
          decoration: BoxDecoration(
            color: lineColor,
            borderRadius: BorderRadius.circular(99),
          ),
        ),
      ],
    );
  }

  Widget _themeChip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.28), width: 0.8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  _ThemePreviewColors _themePreview(WorkOrderPdfTheme theme) {
    switch (theme) {
      case WorkOrderPdfTheme.copperNight:
        return const _ThemePreviewColors(
          paper: Color(0xFFF4E8D6),
          frame: Color(0xFFE0C7A6),
          glow: Color(0x33D49A6B),
          heroText: Color(0xFFFCEAD4),
          cardDark: Color(0xFF222833),
          cardAccent: Color(0xFFB97E54),
          barAccent: Color(0xFFC88D63),
          barAccentMuted: Color(0xFFDEB086),
          barBase: Color(0xFFD6C4AF),
          lineDark: Color(0xFF4A3729),
          lineSoft: Color(0xFFE0D0BD),
        );
      case WorkOrderPdfTheme.forestLedger:
        return const _ThemePreviewColors(
          paper: Color(0xFFEDE7D3),
          frame: Color(0xFFC8CFB8),
          glow: Color(0x336A8B63),
          heroText: Color(0xFFEFF5EA),
          cardDark: Color(0xFF2E3B31),
          cardAccent: Color(0xFF6B8767),
          barAccent: Color(0xFF698667),
          barAccentMuted: Color(0xFF9EB095),
          barBase: Color(0xFFCDD5C3),
          lineDark: Color(0xFF415040),
          lineSoft: Color(0xFFD5DCCB),
        );
      case WorkOrderPdfTheme.signalOrange:
        return const _ThemePreviewColors(
          paper: Color(0xFFF3E5CA),
          frame: Color(0xFFD5C2A5),
          glow: Color(0x33F08947),
          heroText: Color(0xFFFDF3E3),
          cardDark: Color(0xFF2B3640),
          cardAccent: Color(0xFFE56E2E),
          barAccent: Color(0xFFEA7A37),
          barAccentMuted: Color(0xFFF1A56F),
          barBase: Color(0xFFDBCCB2),
          lineDark: Color(0xFF48555E),
          lineSoft: Color(0xFFE5D7BE),
        );
    }
  }

  List<Color> _themeSwatch(WorkOrderPdfTheme theme) {
    switch (theme) {
      case WorkOrderPdfTheme.copperNight:
        return const [Color(0xFF131821), Color(0xFFBF8457), Color(0xFFF1E4D2)];
      case WorkOrderPdfTheme.forestLedger:
        return const [Color(0xFF2A372A), Color(0xFF667D5D), Color(0xFFEDE9D6)];
      case WorkOrderPdfTheme.signalOrange:
        return const [Color(0xFF1F2933), Color(0xFFE56E2E), Color(0xFFF3E5CA)];
    }
  }
}

class _ThemePreviewColors {
  final Color paper;
  final Color frame;
  final Color glow;
  final Color heroText;
  final Color cardDark;
  final Color cardAccent;
  final Color barAccent;
  final Color barAccentMuted;
  final Color barBase;
  final Color lineDark;
  final Color lineSoft;

  const _ThemePreviewColors({
    required this.paper,
    required this.frame,
    required this.glow,
    required this.heroText,
    required this.cardDark,
    required this.cardAccent,
    required this.barAccent,
    required this.barAccentMuted,
    required this.barBase,
    required this.lineDark,
    required this.lineSoft,
  });
}

// ── PDF Preview Screen ────────────────────────────────────────────────────────

class _PdfPreviewScreen extends StatelessWidget {
  final String title;
  final Future<dynamic> Function() buildPdf;

  const _PdfPreviewScreen({required this.title, required this.buildPdf});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgPrimary,
      appBar: AppBar(
        backgroundColor: AppColors.bgSurface,
        title: Text(title,
            style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary)),
        leading: IconButton(
          icon: Icon(Icons.arrow_back_rounded,
              size: 18, color: AppColors.textSecondary),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: PdfPreview(
        build: (format) async {
          final bytes = await buildPdf();
          return bytes as dynamic;
        },
        canChangePageFormat: false,
        canDebug: false,
        pdfFileName: '${title.replaceAll(' ', '_')}.pdf',
        actionBarTheme: PdfActionBarTheme(
          backgroundColor: AppColors.bgSurface,
          iconColor: AppColors.textSecondary,
          textStyle: TextStyle(color: AppColors.textSecondary, fontSize: 12),
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
          SizedBox(height: 12),
          Text(
            hasFilters
                ? 'No closed work orders found'
                : 'Select filters and generate a report',
            style: TextStyle(fontSize: 13, color: AppColors.textTertiary),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
