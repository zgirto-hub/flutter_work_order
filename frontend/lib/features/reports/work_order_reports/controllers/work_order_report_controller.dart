import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '/../models/employee.dart';
import '/../models/workorder_report.dart';

class WorkOrderReportController {

  DateTime? startDate;
  DateTime? endDate;
  String? employeeId;

  List<Employee> employees = [];
    List<WorkOrderReport> results = [];

  bool loading = false;
  bool employeesLoading = true;

  final client = Supabase.instance.client;
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
  /// Load employees
  Future<void> loadEmployees() async {

    employeesLoading = true;

    try {

      final data = await client
          .from('employees')
          .select('id, full_name, shift_type, active, profile_id')
          .eq('active', true)
          .order('full_name');

      employees = (data as List)
          .map((e) => Employee.fromJson(e))
          .toList();

    } catch (e) {
      debugPrint("Employee load error: $e");
    }

    employeesLoading = false;
  }

  /// Generate report
  Future<void> generateReport() async {

    if (employeeId == null || startDate == null || endDate == null) {
      throw Exception("Missing filters");
    }

    loading = true;

    final data = await client.rpc(
      'get_closed_work_orders_report',
      params: {
        'emp_id': employeeId,
        'start_date': startDate!.toIso8601String(),
        'end_date': endDate!.toIso8601String(),
      },
    );

    results = (data as List)
        .map((e) => WorkOrderReport.fromJson(e))
        .toList();

    loading = false;
  }

}