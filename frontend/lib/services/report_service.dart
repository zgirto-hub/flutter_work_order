import 'dart:convert';
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
}
