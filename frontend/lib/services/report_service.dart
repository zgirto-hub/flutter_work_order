import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import '../models/workorder_report.dart';
import '../config.dart';

class ReportService {
  String _errorDetail(http.Response res, String fallback) {
    try {
      final body = jsonDecode(res.body);
      return (body is Map ? body['detail'] : null) ?? fallback;
    } catch (_) {
      return fallback;
    }
  }

  /// Fetch closed work orders for a technician in a date range.
  /// Replaces the direct Supabase RPC call in WorkOrderReportScreen.
  Future<List<WorkOrderReport>> getClosedWorkOrders({
    required String technicianId,
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    final uri = Uri.parse('${AppConfig.baseUrl}/reports/closed-work-orders').replace(
      queryParameters: {
        'technician_id': technicianId,
        'start_date': startDate.toIso8601String(),
        'end_date': endDate.toIso8601String(),
      },
    );
    final res = await http.get(uri);
    if (res.statusCode != 200) {
      throw Exception(_errorDetail(res, 'Failed to fetch work orders'));
    }
    final data = jsonDecode(res.body) as List;
    return data.map((e) => WorkOrderReport.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// Generate the monthly tasks PDF on the backend and return the raw bytes.
  /// Pass the bytes directly to PdfPreviewScreen — no second network call needed.
  Future<Uint8List> generateMonthlyTasksReport({
    required String name,
    required String startDate,  // e.g. "01 Jan 2026"
    required String endDate,    // e.g. "31 Jan 2026"
    required List<Map<String, String>> tasks,
    // Optional profile fields — kept for future use when users table is extended:
    String department = 'Navigational Equipment Department',
    String section    = 'AFTN/AMHS Section',
    String title      = '',
    String dgcaId     = '—',
    String civilId    = '—',
  }) async {
    final uri = Uri.parse('${AppConfig.baseUrl}/reports/monthly-tasks');
    final res = await http.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'name':       name,
        'start_date': startDate,
        'end_date':   endDate,
        'tasks':      tasks,
        'department': department,
        'section':    section,
        'title':      title,
        'dgca_id':    dgcaId,
        'civil_id':   civilId,
      }),
    );
    if (res.statusCode != 200) {
      throw Exception(_errorDetail(res, 'Failed to generate report'));
    }
    return res.bodyBytes;
  }
}
