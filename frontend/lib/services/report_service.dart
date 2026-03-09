import 'dart:convert';
import 'package:http/http.dart' as http;

import '../config.dart';
import '../models/workorder_report.dart';

class ReportService {
  static Future<List<WorkOrderReport>> getClosedWorkOrders({
    required String employeeId,
    required DateTime startDate,
    required DateTime endDate,
  }) async {

    final url = Uri.parse(
      "${AppConfig.baseUrl}/workorders/report"
      "?employee=$employeeId"
      "&start=${startDate.toIso8601String()}"
      "&end=${endDate.toIso8601String()}",
    );

    final response = await http.get(url);

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);

      return (data as List)
          .map((e) => WorkOrderReport.fromJson(e))
          .toList();
    }

    throw Exception("Failed to load report");
  }
}