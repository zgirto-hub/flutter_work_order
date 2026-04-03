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
    final uri =
        Uri.parse('${AppConfig.baseUrl}/reports/closed-work-orders').replace(
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
    return data
        .map((e) => WorkOrderReport.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Export a work order as a PDF report.
  /// Returns raw PDF bytes from the server.
  Future<Uint8List> exportWorkOrderPdf({
    required String workOrderId,
    required String email,
    required String userRole,
  }) async {
    final uri = Uri.parse(
      '${AppConfig.baseUrl}/reports/work-order-pdf/$workOrderId',
    ).replace(queryParameters: {
      'email': email,
      'user_role': userRole,
    });
    final res = await http.post(uri);
    if (res.statusCode != 200) {
      throw Exception(_errorDetail(res, 'Failed to generate PDF'));
    }
    return res.bodyBytes;
  }
}
