import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:file_picker/file_picker.dart';
import '../models/work_order.dart';
import '../models/work_order_comment.dart';
import '../models/work_order_attachment.dart';
import '../config.dart';

class WorkOrderService {
  String get _email =>
      Supabase.instance.client.auth.currentUser?.email ?? '';

  String get _userId =>
      Supabase.instance.client.auth.currentUser?.id ?? '';

  String _errorDetail(http.Response res, String fallback) {
    try {
      final body = jsonDecode(res.body);
      if (body is! Map) return fallback;
      final detail = body['detail'];
      if (detail is String) return detail;
      if (detail is List) {
        // FastAPI 422 validation error format
        return detail
            .map((e) => e is Map ? '${e['loc']?.last ?? ''}: ${e['msg'] ?? ''}' : e.toString())
            .join(', ');
      }
      return fallback;
    } catch (_) {
      return fallback;
    }
  }

  Future<({List<WorkOrder> items, int total})> fetchWorkOrders({
    String? status,
    String? type,
    String? department,
    String? userRole,
    int? limit,
    int offset = 0,
  }) async {
    final params = <String, String>{
      'email': _email,
      'user_role': userRole ?? '',
      'offset': '$offset',
    };
    if (status != null) params['status'] = status;
    if (type != null) params['type'] = type;
    if (department != null) params['department_id'] = department;
    if (limit != null) params['limit'] = '$limit';

    final uri = Uri.parse('${AppConfig.baseUrl}/work-orders')
        .replace(queryParameters: params);

    final res = await http.get(uri);
    if (res.statusCode != 200) {
      throw Exception('Failed to fetch work orders');
    }
    final data = jsonDecode(res.body);
    final items = (data['work_orders'] as List)
        .map((j) => WorkOrder.fromJson(j))
        .toList();
    final total = data['total'] as int? ?? items.length;
    return (items: items, total: total);
  }

  Future<WorkOrder> addWorkOrder(WorkOrder workOrder) async {
    final res = await http.post(
      Uri.parse('${AppConfig.baseUrl}/work-orders'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'job_no': workOrder.jobNo,
        'title': workOrder.title,
        'description': workOrder.description,
        'location': workOrder.location,
        'mobile_number': workOrder.mobileNumber,
        'department_id': workOrder.departmentId,
        'type': workOrder.type,
        'status': workOrder.status,
        'created_by': _userId,
        'created_by_email': _email,
        'assigned_technician_ids':
            workOrder.assignedTechnicians.map((e) => e.id).toList(),
      }),
    );

    if (res.statusCode != 200) {
      final errorMsg = _errorDetail(res, 'Failed to create work order');
      throw Exception('Error ${res.statusCode}: $errorMsg\nRAW: ${res.body}');
    }

    final data = jsonDecode(res.body);
    return WorkOrder.fromJson(data['work_order']);
  }

  Future<void> updateWorkOrder(WorkOrder workOrder) async {
    final res = await http.put(
      Uri.parse(
          '${AppConfig.baseUrl}/work-orders/${workOrder.id}?user_email=${Uri.encodeComponent(_email)}'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'job_no': workOrder.jobNo,
        'title': workOrder.title,
        'description': workOrder.description,
        'location': workOrder.location,
        'mobile_number': workOrder.mobileNumber,
        'department_id': workOrder.departmentId,
        'type': workOrder.type,
        'status': workOrder.status,
        'assigned_technician_ids':
            workOrder.assignedTechnicians.map((e) => e.id).toList(),
      }),
    );

    if (res.statusCode != 200) {
      throw Exception(_errorDetail(res, 'Failed to update work order'));
    }
  }

  Future<void> closeWorkOrder(
    String id, {
    required String closedBy,
    String? techNotes,
  }) async {
    final res = await http.patch(
      Uri.parse('${AppConfig.baseUrl}/work-orders/$id/close?user_email=${Uri.encodeComponent(_email)}'),
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

  Future<void> deleteWorkOrder(String id) async {
    final res = await http.delete(
      Uri.parse(
          '${AppConfig.baseUrl}/work-orders/$id?user_email=${Uri.encodeComponent(_email)}'),
    );

    if (res.statusCode != 200) {
      throw Exception(_errorDetail(res, 'Failed to delete work order'));
    }
  }

  Future<void> deleteWorkOrders(List<String> ids) async {
    final res = await http.delete(
      Uri.parse(
          '${AppConfig.baseUrl}/work-orders?ids=${ids.join(",")}&user_email=${Uri.encodeComponent(_email)}'),
    );

    if (res.statusCode != 200) {
      throw Exception(_errorDetail(res, 'Failed to delete work orders'));
    }
  }

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
    String type = 'comment',
  }) async {
    final res = await http.post(
      Uri.parse('${AppConfig.baseUrl}/work-orders/$workOrderId/comments'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'author_email': authorEmail,
        'author_name': authorName,
        'body': body,
        'type': type,
      }),
    );
    if (res.statusCode == 200) {
      final data = jsonDecode(res.body);
      return WorkOrderComment.fromJson(data['comment']);
    }
    return null;
  }

  Future<Map<String, dynamic>?> getEmployeeProfile() async {
    final res = await http.get(
      Uri.parse('${AppConfig.baseUrl}/users/me?email=${Uri.encodeComponent(_email)}'),
    );
    if (res.statusCode == 200) {
      final data = jsonDecode(res.body);
      return data['user'];
    }
    return null;
  }

  Future<List<WorkOrderAttachment>> fetchAttachments(String workOrderId) async {
    final res = await http.get(
      Uri.parse('${AppConfig.baseUrl}/work-orders/$workOrderId/attachments'),
    );
    if (res.statusCode == 200) {
      final data = jsonDecode(res.body);
      return (data['attachments'] as List)
          .map((j) => WorkOrderAttachment.fromJson(j))
          .toList();
    }
    return [];
  }

  Future<WorkOrderAttachment?> uploadAttachment({
    required String workOrderId,
    required PlatformFile file,
    Function(int)? onProgress,
  }) async {
    try {
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('${AppConfig.baseUrl}/work-orders/$workOrderId/attachments'),
      );

      request.fields['uploaded_by'] = _email;

      if (file.bytes != null) {
        request.files.add(http.MultipartFile.fromBytes(
          'file',
          file.bytes!,
          filename: file.name,
        ));
      } else if (file.path != null) {
        request.files.add(await http.MultipartFile.fromPath(
          'file',
          file.path!,
          filename: file.name,
        ));
      } else {
        return null;
      }

      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final attachments = await fetchAttachments(workOrderId);
        return attachments.isNotEmpty ? attachments.last : null;
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  Future<bool> deleteAttachment(String workOrderId, String attachmentId) async {
    final res = await http.delete(
      Uri.parse('${AppConfig.baseUrl}/work-orders/$workOrderId/attachments/$attachmentId?email=${Uri.encodeComponent(_email)}'),
    );
    return res.statusCode == 200;
  }

  Future<PlatformFile?> pickAttachment() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'doc', 'docx', 'jpg', 'jpeg', 'png', 'gif'],
      withData: true,
    );
    return result?.files.isNotEmpty == true ? result!.files.first : null;
  }
}
