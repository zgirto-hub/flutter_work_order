import 'package:flutter/material.dart';
import '../../../../models/employee.dart';

class ReportFiltersSection extends StatelessWidget {

  final List<Employee> employees;
  final bool employeesLoading;
  final String? employeeId;
  final DateTime? startDate;
  final DateTime? endDate;
  final bool loading;

  final Function(String?) onEmployeeChanged;
  final VoidCallback onStartDatePick;
  final VoidCallback onEndDatePick;
  final VoidCallback onGenerate;

  const ReportFiltersSection({
    super.key,
    required this.employees,
    required this.employeesLoading,
    required this.employeeId,
    required this.startDate,
    required this.endDate,
    required this.loading,
    required this.onEmployeeChanged,
    required this.onStartDatePick,
    required this.onEndDatePick,
    required this.onGenerate,
  });

  @override
  Widget build(BuildContext context) {

    return Column(
      children: [

        /// Employee dropdown
        employeesLoading
            ? const Center(child: CircularProgressIndicator())
            : employees.isEmpty
                ? const Text("No employees available")
                : DropdownButtonFormField<String>(
                    isDense: true,
                    value: employeeId,
                    decoration: const InputDecoration(
                      labelText: "Employee",
                      border: OutlineInputBorder(),
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                    items: employees
                        .map((emp) => DropdownMenuItem(
                              value: emp.id,
                              child: Text(emp.fullName),
                            ))
                        .toList(),
                    onChanged: onEmployeeChanged,
                  ),

        const SizedBox(height: 16),

        /// Date pickers
        Row(
          children: [

            Expanded(
              child: OutlinedButton.icon(
                icon: const Icon(Icons.calendar_today, size: 16),
                onPressed: onStartDatePick,
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
                onPressed: onEndDatePick,
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

        /// Generate button
        SizedBox(
          height: 42,
          child: ElevatedButton(
            onPressed: loading ? null : onGenerate,
            child: const Text("Generate Report"),
          ),
        ),

        const SizedBox(height: 20),
      ],
    );
  }
}