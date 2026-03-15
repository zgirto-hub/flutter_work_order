import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import '../models/request_model.dart';
import '../config.dart';

class RequestService {
  Future<String> getUserRole(String email) async {
    final res = await http.get(
      Uri.parse('${AppConfig.baseUrl}/user-role?email=${Uri.encodeComponent(email)}'),
    );
    if (res.statusCode == 200) {
      final data = jsonDecode(res.body);
      return data['user_type'] as String? ?? 'admin';
    }
    return 'admin';
  }

  Future<List<RequestModel>> fetchRequests({
    required String email,
    required String userRole,
  }) async {
    final res = await http.get(
      Uri.parse(
        '${AppConfig.baseUrl}/requests?email=${Uri.encodeComponent(email)}&user_role=${Uri.encodeComponent(userRole)}',
      ),
    );
    if (res.statusCode == 200) {
      final data = jsonDecode(res.body);
      final list = data['requests'] as List<dynamic>;
      return list.map((j) => RequestModel.fromJson(j as Map<String, dynamic>)).toList();
    }
    return [];
  }

  /// Creates a request and returns the new request ID.
  Future<String> createRequest({
    required String title,
    required String description,
    required String createdBy,
    required String requesterName,
    required String location,
  }) async {
    final res = await http.post(
      Uri.parse('${AppConfig.baseUrl}/requests'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'title': title,
        'description': description,
        'created_by': createdBy,
        'requester_name': requesterName,
        'location': location,
      }),
    );
    if (res.statusCode != 200) {
      throw Exception(jsonDecode(res.body)['detail'] ?? 'Failed to create request');
    }
    final data = jsonDecode(res.body);
    final id = data['id'];
    if (id == null) throw Exception('Request created but ID was not returned');
    return id.toString();
  }

  Future<void> updateRequest({
    required String id,
    required String title,
    required String description,
    required String requesterName,
    required String location,
    required String email,
  }) async {
    final res = await http.post(
      Uri.parse('${AppConfig.baseUrl}/requests/$id/update'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'title': title,
        'description': description,
        'requester_name': requesterName,
        'location': location,
        'email': email,
      }),
    );
    if (res.statusCode != 200) {
      throw Exception(jsonDecode(res.body)['detail'] ?? 'Failed to update request');
    }
  }

  Future<void> deleteRequest({
    required String id,
    required String email,
  }) async {
    final res = await http.delete(
      Uri.parse('${AppConfig.baseUrl}/requests/$id?email=${Uri.encodeComponent(email)}'),
    );
    if (res.statusCode != 200) {
      throw Exception(jsonDecode(res.body)['detail'] ?? 'Failed to delete request');
    }
  }

  Future<void> closeRequest({
    required String id,
    required String closedBy,
    String? techNotes,
  }) async {
    final res = await http.patch(
      Uri.parse('${AppConfig.baseUrl}/requests/$id/close'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'closed_by': closedBy,
        'tech_notes': techNotes,
      }),
    );
    if (res.statusCode != 200) {
      throw Exception(jsonDecode(res.body)['detail'] ?? 'Failed to close request');
    }
  }

  // ── Attachments ─────────────────────────────────────────────────────────────

  Future<void> uploadAttachment({
    required String requestId,
    required String uploadedBy,
    required String fileName,
    required Uint8List bytes,
    String? mimeType,
  }) async {
    final uri = Uri.parse('${AppConfig.baseUrl}/requests/$requestId/attachments');
    final request = http.MultipartRequest('POST', uri);
    request.fields['uploaded_by'] = uploadedBy;
    request.files.add(http.MultipartFile.fromBytes(
      'file',
      bytes,
      filename: fileName,
    ));
    final streamed = await request.send();
    if (streamed.statusCode != 200) {
      throw Exception('Failed to upload attachment: ${streamed.statusCode}');
    }
  }

  Future<List<Map<String, dynamic>>> fetchAttachments(String requestId) async {
    final res = await http.get(
      Uri.parse('${AppConfig.baseUrl}/requests/$requestId/attachments'),
    );
    if (res.statusCode == 200) {
      final data = jsonDecode(res.body);
      return List<Map<String, dynamic>>.from(data['attachments'] as List);
    }
    return [];
  }

  Future<void> deleteAttachment({
    required String requestId,
    required String attachmentId,
    required String email,
  }) async {
    final res = await http.delete(
      Uri.parse(
        '${AppConfig.baseUrl}/requests/$requestId/attachments/$attachmentId?email=${Uri.encodeComponent(email)}',
      ),
    );
    if (res.statusCode != 200) {
      throw Exception(jsonDecode(res.body)['detail'] ?? 'Failed to delete attachment');
    }
  }
}
