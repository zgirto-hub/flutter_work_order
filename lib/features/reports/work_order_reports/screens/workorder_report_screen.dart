import 'package:flutter/material.dart';
import '../../../../models/workorder_report.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../models/employee.dart';
import 'package:pdf/pdf.dart';
import '../../../../services/pdf/work_order_pdf_service.dart';
import '../widgets/report_summary_section.dart';
import '../widgets/report_table_section.dart';
import '../widgets/report_filters_section.dart';
import '../controllers/work_order_report_controller.dart';

class WorkOrderReportScreen extends StatefulWidget {
  const WorkOrderReportScreen({super.key});

  @override
  State<WorkOrderReportScreen> createState() => _WorkOrderReportScreenState();
}

class _WorkOrderReportScreenState extends State<WorkOrderReportScreen> {


  DateTime? startDate;
  DateTime? endDate;
  String? employeeId;
  List<Employee> employees = [];
   List<WorkOrderReport> results = [];
  bool loading = false;
  Set<int> expandedRows = {};
  bool employeesLoading = true;

  final controller = WorkOrderReportController();

Future<void> _pickStartDate() async {
  final date = await showDatePicker(
    context: context,
    firstDate: DateTime(2020),
    lastDate: DateTime.now(),
    initialDate: DateTime.now(),
  );

  if (date != null) {
    setState(() {
      controller.startDate = date;
    });
  }
}

  Future<void> _pickEndDate() async {
    final date = await showDatePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDate: DateTime.now(),
    );

    if (date != null) {
      setState(() => endDate = date);
    }
  }
  Future<void> _exportPdf() async {

  final themeColor = Theme.of(context).colorScheme.primary;

  await WorkOrderPdfService.exportReport(
    employeeName: selectedEmployeeName,
    startDate: controller.startDate!,
    endDate: controller.endDate!,
    results: results,

    primaryColor: PdfColor(
      themeColor.red / 255,
      themeColor.green / 255,
      themeColor.blue / 255,
    ),
  );
}

String get selectedEmployeeName {
  final emp = employees.firstWhere(
    (e) => e.id == employeeId,
    orElse: () => const Employee(
      id: '',
      fullName: '',
      shiftType: '',
      active: false,
    ),
  );

  return emp.fullName;
}
Future<void> _generateReport() async {
  if (employeeId == null || startDate == null || endDate == null) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Please select employee and date range")),
    );
    return;
  }

  setState(() {
    loading = true;
    results = [];
  });

  try {
    
final data = await Supabase.instance.client.rpc(
  'get_closed_work_orders_report',
  params: {
    'emp_id': employeeId,
    'start_date': startDate!.toIso8601String(),
    'end_date': endDate!.toIso8601String(),
  },
);



final list = (data as List)
    .map((e) => WorkOrderReport.fromJson(e))
    .toList();

if (!mounted) return;

setState(() {
  results = list;
});
  } catch (e) {
    print("Report error: $e");

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Failed to load report")),
    );
  }

if (!mounted) return;

setState(() {
  loading = false;
});
}

Future<void> loadEmployees() async {
  try {
    final data = await Supabase.instance.client
        .from('employees')
        .select('id, full_name, shift_type, active, profile_id')
        .eq('active', true)
        .order('full_name');

    final list = (data as List)
        .map((e) => Employee.fromJson(e))
        .toList();

    if (!mounted) return;

    setState(() {
      employees = list;
      employeesLoading = false;
    });

  } catch (e) {
    if (!mounted) return;

    setState(() {
      employeesLoading = false;
    });

    debugPrint("Error loading employees: $e");
  }
}
@override
void initState() {
  super.initState();

  controller.loadEmployees().then((_) {
    setState(() {});
  });
}
  @override
  Widget build(BuildContext context) {

    return Scaffold(
      appBar: AppBar(
        title: const Text("Work Order Reports"),
      ),

  body: Padding(
  padding: const EdgeInsets.all(16),
  child: Column(
          children: [

  ReportFiltersSection(
    employees: controller.employees,
    employeesLoading: controller.employeesLoading,
    employeeId: controller.employeeId,
    startDate: controller.startDate,
    endDate: controller.endDate,
    loading: controller.loading,

    onEmployeeChanged: (value) {
      setState(() {
        controller.employeeId = value;
      });
    },

    onStartDatePick: _pickStartDate,
    onEndDatePick: _pickEndDate,

    onGenerate: () async {
      try {
        await controller.generateReport();
        setState(() {});
      } catch (_) {
        if (!mounted) return;

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Please select employee and date range"),
          ),
        );
      }
    },
  ),

  const SizedBox(height: 20),

  if (controller.startDate != null && controller.endDate != null)
  ReportSummarySection(
    employeeName: selectedEmployeeName,
    startDate: controller.startDate!,
    endDate: controller.endDate!,
    total: controller.results.length,
    onExport: _exportPdf,
  ),

  const SizedBox(height: 10),

  Expanded(
    child: controller.loading
        ? const Center(child: CircularProgressIndicator())
        : ReportTableSection(results: controller.results),
  ),
]
      ),
    ),
  );
}
}
