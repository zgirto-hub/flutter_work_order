import 'package:flutter/material.dart';

import '../../models/workorder_report.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/employee.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import 'package:pdf/pdf.dart';

import '../../services/pdf/work_order_pdf_service.dart';

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

  Future<void> _pickStartDate() async {
    final date = await showDatePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDate: DateTime.now(),
    );

    if (date != null) {
      setState(() => startDate = date);
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
    startDate: startDate!,
    endDate: endDate!,
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
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Please select employee and date range")),
    );
    return;
  }
print("Employee: $employeeId");
print("Start: $startDate");
print("End: $endDate");
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

print("Report raw data: $data");

final list = (data as List)
    .map((e) => WorkOrderReport.fromJson(e))
    .toList();

setState(() {
  results = list;
});
  } catch (e) {
    print("Report error: $e");

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Failed to load report")),
    );
  }

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

    print("Supabase response: $data");

    final list = (data as List)
        .map((e) => Employee.fromJson(e))
        .toList();

    setState(() {
      employees = list;
    });

    print("Employees loaded: ${employees.length}");
  } catch (e) {
    print("Error loading employees: $e");
  }
}
@override
void initState() {
  super.initState();
  loadEmployees();
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

            /// Employee
employees.isEmpty
    ? const Center(child: CircularProgressIndicator())
    
    : DropdownButtonFormField<String>(
        value: employeeId,
        decoration: const InputDecoration(
          labelText: "Employee",
          border: OutlineInputBorder(),
        ),
        items: employees
            .map((emp) => DropdownMenuItem(
                  value: emp.id,
                  child: Text(emp.fullName),
                ))
            .toList(),
        onChanged: (value) {
          setState(() {
            employeeId = value;
          });
        },
      ),

            const SizedBox(height: 16),

            /// Dates
            Row(
              children: [

                Expanded(
                  child: OutlinedButton(
                    onPressed: _pickStartDate,
                    child: Text(
                      startDate == null
                          ? "Start Date"
                          : startDate!.toString().split(" ")[0],
                    ),
                  ),
                ),

                const SizedBox(width: 10),

                Expanded(
                  child: OutlinedButton(
                    onPressed: _pickEndDate,
                    child: Text(
                      endDate == null
                          ? "End Date"
                          : endDate!.toString().split(" ")[0],
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),

            /// Generate
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: loading ? null : _generateReport,
                child: const Text("Generate Report"),
              ),
            ),

            const SizedBox(height: 20),
           _buildReportSummary(),

if (results.isNotEmpty)
  Align(
    alignment: Alignment.centerRight,
    child: ElevatedButton.icon(
      icon: const Icon(Icons.picture_as_pdf),
      label: const Text("Export PDF"),
      onPressed: _exportPdf,
    ),
  ),

const SizedBox(height: 10),
            /// Results
 /// Results
Expanded(
  child: loading
      ? const Center(child: CircularProgressIndicator())
      : results.isEmpty
          ? const Center(child: Text("No results"))
          : LayoutBuilder(
              builder: (context, constraints) {

                final isLandscape =
                    MediaQuery.of(context).orientation ==
                        Orientation.landscape;

                return SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minWidth: constraints.maxWidth,
                    ),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.vertical,
                      child: DataTable(
                        columnSpacing: 30,
                        headingRowHeight: 42,
                        dataRowHeight: 50,
                        columns: const [
                          DataColumn(label: Text("Title")),
                          DataColumn(label: Text("Location")),
                          DataColumn(label: Text("Closed")),
                        ],
                        rows: results.map((item) {
                          return DataRow(
                            cells: [

                              /// Title
                              DataCell(
                                Container(
                                  alignment: Alignment.centerLeft,
                                  width: isLandscape ? 420 : 220,
                                  child: Text(
                                    item.title,
                                    textAlign: TextAlign.left,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ),

                              /// Location
                              DataCell(
                                Container(
                                  alignment: Alignment.centerLeft,
                                  width: 140,
                                  child: Text(item.location),
                                ),
                              ),

                              /// Closed Date
                              DataCell(
                                Container(
                                  alignment: Alignment.centerLeft,
                                  width: 120,
                                  child: Text(
                                    item.modifiedDate
                                        .toString()
                                        .split(" ")[0],
                                  ),
                                ),
                              ),
                            ],
                          );
                        }).toList(),
                      ),
                    ),
                  ),
                );
              },
            ),
)
          ],
        ),
      ),
    );
  }
  Widget _buildReportSummary() {
  if (results.isEmpty) return const SizedBox();

  return Card(
    elevation: 2,
    margin: const EdgeInsets.only(bottom: 16),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [

          const Text(
            "Report Summary",
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),

          const SizedBox(height: 10),

          Text("Employee: $selectedEmployeeName"),

          Text(
            "Date Range: "
            "${startDate!.toString().split(' ')[0]} to "
            "${endDate!.toString().split(' ')[0]}",
          ),

          const SizedBox(height: 6),

          Text(
            "Total Closed Work Orders: ${results.length}",
            style: const TextStyle(
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    ),
  );
}
}
