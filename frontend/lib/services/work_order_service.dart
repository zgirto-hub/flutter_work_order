import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/work_order.dart';
import '../models/work_order_comment.dart';
import '../config.dart';

class WorkOrderService {
  String get _email =>
      Supabase.instance.client.auth.currentUser?.email ?? '';

  String get _userId =>
      Supabase.instance.client.auth.currentUser?.id ?? '';

  /// Extracts a human-readable error message from a non-200 response,
  /// handling both JSON `{"detail": "..."}` and plain-text bodies.
  String _errorDetail(http.Response res, String fallback) {
    try {
      final body = jsonDecode(res.body);
      return (body is Map ? body['detail'] : null) ?? fallback;
    } catch (_) {
      return fallback;
    }
  }

  // ── Fetch all work orders ──────────────────────────────────────────────────

  Future<List<WorkOrder>> fetchWorkOrders({
    String? status,
    String? type,
    String? requestId,
  }) async {
    final params = <String, String>{};
    if (status != null) params['status'] = status;
    if (type != null) params['type'] = type;
    if (requestId != null) params['request_id'] = requestId;

    final uri = Uri.parse('${AppConfig.baseUrl}/work-orders')
        .replace(queryParameters: params.isNotEmpty ? params : null);

    final res = await http.get(uri);
    if (res.statusCode != 200) {
      throw Exception('Failed to fetch work orders');
    }
    final data = jsonDecode(res.body);
    return (data['work_orders'] as List)
        .map((j) => WorkOrder.fromJson(j))
        .toList();
  }

  // ── Add work order ─────────────────────────────────────────────────────────

  Future<WorkOrder> addWorkOrder(WorkOrder workOrder, {String? sourceRequestId}) async {
    final res = await http.post(
      Uri.parse('${AppConfig.baseUrl}/work-orders'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'job_no': workOrder.jobNo,
        'title': workOrder.Title,
        'description': workOrder.description,
        'location': workOrder.location,
        'type': workOrder.type,
        'status': workOrder.status,
        'created_by': _userId,
        'created_by_email': _email,
        'assigned_employee_ids':
            workOrder.assignedEmployees.map((e) => e.id).toList(),
        'source_request_id': sourceRequestId,
      }),
    );

    if (res.statusCode != 200) {
      throw Exception(_errorDetail(res, 'Failed to create work order'));
    }

    final data = jsonDecode(res.body);
    return WorkOrder.fromJson(data['work_order']);
  }

  // ── Update work order ──────────────────────────────────────────────────────

  Future<void> updateWorkOrder(WorkOrder workOrder) async {
    final res = await http.patch(
      Uri.parse(
          '${AppConfig.baseUrl}/work-orders/${workOrder.id}?user_email=${Uri.encodeComponent(_email)}'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'job_no': workOrder.jobNo,
        'title': workOrder.Title,
        'description': workOrder.description,
        'location': workOrder.location,
        'type': workOrder.type,
        'status': workOrder.status,
        'assigned_employee_ids':
            workOrder.assignedEmployees.map((e) => e.id).toList(),
      }),
    );

    if (res.statusCode != 200) {
      throw Exception(_errorDetail(res, 'Failed to update work order'));
    }
  }

  // ── Close work order ───────────────────────────────────────────────────────

  Future<void> closeWorkOrder(
    String id, {
    required String closedBy,
    String? techNotes,
  }) async {
    final res = await http.patch(
      Uri.parse('${AppConfig.baseUrl}/work-orders/$id/close'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'closed_by': closedBy,
        'tech_notes': techNotes,
      }),
    );

    if (res.statusCode != 200) {
      throw Exception(_errorDetail(res, 'Failed to close work order'));
    }
  }

  // ── Delete single work order ───────────────────────────────────────────────

  Future<void> deleteWorkOrder(String id) async {
    final res = await http.delete(
      Uri.parse(
          '${AppConfig.baseUrl}/work-orders/$id?user_email=${Uri.encodeComponent(_email)}'),
    );

    if (res.statusCode != 200) {
      throw Exception(_errorDetail(res, 'Failed to delete work order'));
    }
  }

  // ── Delete multiple work orders ────────────────────────────────────────────

  Future<void> deleteWorkOrders(List<String> ids) async {
    final res = await http.delete(
      Uri.parse(
          '${AppConfig.baseUrl}/work-orders?ids=${ids.join(",")}&user_email=${Uri.encodeComponent(_email)}'),
    );

    if (res.statusCode != 200) {
      throw Exception(_errorDetail(res, 'Failed to delete work orders'));
    }
  }

  // ── Comments ───────────────────────────────────────────────────────────────

  Future<WorkOrder?> fetchWorkOrderById(String id) async {
    final res = await http.get(
      Uri.parse('${AppConfig.baseUrl}/work-orders/$id'),
    );
    if (res.statusCode != 200) {
      return null;
    }
    final data = jsonDecode(res.body);
    final wo = data['work_order'];
    if (wo is! Map<String, dynamic>) return null;
    return WorkOrder.fromJson(wo);
  }

  Future<List<WorkOrderComment>> fetchComments(String workOrderId) async {
    final res = await http.get(
      Uri.parse('${AppConfig.baseUrl}/work-orders/$workOrderId/comments'),
    );
    if (res.statusCode == 200) {
      final data = jsonDecode(res.body);
      return (data['comments'] as List)
          .map((j) => WorkOrderComment.fromJson(j))
          .toList();
    }
    return [];
  }

  Future<WorkOrderComment?> addComment({
    required String workOrderId,
    required String authorEmail,
    required String authorName,
    required String body,
  }) async {
    final res = await http.post(
      Uri.parse('${AppConfig.baseUrl}/work-orders/$workOrderId/comments'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'author_email': authorEmail,
        'author_name': authorName,
        'body': body,
        'type': 'comment',
      }),
    );
    if (res.statusCode == 200) {
      final data = jsonDecode(res.body);
      return WorkOrderComment.fromJson(data['comment']);
    }
    return null;
  }
}
