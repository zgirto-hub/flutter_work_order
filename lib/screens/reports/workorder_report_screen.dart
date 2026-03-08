import 'package:flutter/material.dart';

import '../../models/workorder_report.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/employee.dart';
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
  Set<int> expandedRows = {};
  bool employeesLoading = true;

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
employeesLoading
    ? const Center(child: CircularProgressIndicator())
    
    : employeesLoading
    ? const Center(child: CircularProgressIndicator())
    : employees.isEmpty
        ? const Text("No employees available")
        : DropdownButtonFormField<String>(
            isDense: true,
            value: employeeId,
            decoration: const InputDecoration(
              labelText: "Employee",
              border: OutlineInputBorder(),
              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
                  child: OutlinedButton.icon(
                            icon: const Icon(Icons.calendar_today, size: 16),
                            onPressed: _pickStartDate,
                            label: Text(
                          startDate == null
                          ? "Start Date"
                          : startDate!.toString().split(" ")[0],
                    ),
                  ),
                ),

                const SizedBox(width: 10),

                Expanded(
                  child: OutlinedButton.icon(
                        icon: const Icon(Icons.calendar_today, size: 16),
                        onPressed: _pickEndDate,
                        label: Text(
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
                height: 42,
                child: ElevatedButton(
                onPressed: loading ? null : _generateReport,
                child: const Text("Generate Report"),
              ),
            ),

            const SizedBox(height: 20),
           _buildReportSummary(),



const SizedBox(height: 10),
            /// Results
 /// Results
Expanded(
  child: loading
      ? const Center(child: CircularProgressIndicator())
      : results.isEmpty
          ? Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: const [
                Icon(Icons.assignment_outlined, size: 48, color: Colors.grey),
                SizedBox(height: 10),
                Text("No work orders found"),
              ],
            )
          : SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SingleChildScrollView(
                scrollDirection: Axis.vertical,
                child: DataTable(
                  columnSpacing: 30,
                  headingRowHeight: 42,
                  columns: const [
                    DataColumn(label: Text("Title")),
                    DataColumn(label: Text("Location")),
                    DataColumn(label: Text("Closed")),
                  ],
                  rows: results.asMap().entries.map((entry) {
                    final index = entry.key;
                    final item = entry.value;

                    return DataRow(
                      cells: [
                        DataCell(
                          GestureDetector(
                            onTap: () {
                              setState(() {
                                if (expandedRows.contains(index)) {
                                  expandedRows.remove(index);
                                } else {
                                  expandedRows.add(index);
                                }
                              });
                            },
                            child: SizedBox(
                              width: 260,
                              child: AnimatedSize(
                                duration: const Duration(milliseconds: 250),
                                curve: Curves.easeInOut,
                                alignment: Alignment.topLeft,
                                child: Text(
                                  item.title,
                                  maxLines:
                                      expandedRows.contains(index) ? null : 1,
                                  overflow: expandedRows.contains(index)
                                      ? TextOverflow.visible
                                      : TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                          ),
                        ),

                        DataCell(
                          SizedBox(
                            width: 140,
                            child: Text(item.location),
                          ),
                        ),

                        DataCell(
                          SizedBox(
                            width: 120,
                            child: Text(
                              item.modifiedDate.toString().split(" ")[0],
                            ),
                          ),
                        ),
                      ],
                    );
                  }).toList(),
                ),
              ),
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


      /// Header + Export Button
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text(
            "Report Summary",
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),

          ElevatedButton.icon(
            icon: const Icon(Icons.picture_as_pdf),
            label: const Text("Export PDF"),
            onPressed: _exportPdf,
          ),
        ],
      ),

      const SizedBox(height: 12),

      Text("Employee: $selectedEmployeeName"),

      Text(
        "Date Range: "
        "${startDate!.toString().split(' ')[0]} to "
        "${endDate!.toString().split(' ')[0]}",
      ),

      const SizedBox(height: 8),

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
