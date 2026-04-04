import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/work_order_signature.dart';
import '../config.dart';

class SignatureService {
  String get _email => Supabase.instance.client.auth.currentUser?.email ?? '';

  Future<List<WorkOrderSignature>> fetchSignatures(String workOrderId) async {
    final res = await http.get(
      Uri.parse('${AppConfig.baseUrl}/work-orders/$workOrderId/signatures'),
    );
    if (res.statusCode != 200) {
      throw Exception('Failed to fetch signatures');
    }
    final data = jsonDecode(res.body);
    return (data['signatures'] as List)
        .map((j) => WorkOrderSignature.fromJson(j))
        .toList();
  }

  Future<WorkOrderSignature> saveSignature({
    required String workOrderId,
    required String signerEmail,
    required String signerRole,
    String? signatureData,
    bool useSaved = false,
  }) async {
    if (!useSaved && (signatureData == null || signatureData.isEmpty)) {
      throw Exception(
          'Signature data is required when not using a saved signature');
    }

    final payload = <String, dynamic>{
      'signer_email': signerEmail,
      'signer_role': signerRole,
    };
    if (useSaved) {
      payload['use_saved'] = true;
    } else {
      payload['signature_data'] = signatureData;
    }

    final res = await http.post(
      Uri.parse('${AppConfig.baseUrl}/work-orders/$workOrderId/signatures'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(payload),
    );
    if (res.statusCode != 200) {
      final detail = _errorDetail(res, 'Failed to save signature');
      throw Exception(detail);
    }
    final data = jsonDecode(res.body);
    return WorkOrderSignature.fromJson(data['signature']);
  }

  Future<void> updateSignature({
    required String workOrderId,
    required String signatureId,
    required String status,
    String? rejectionReason,
  }) async {
    final uri = Uri.parse(
      '${AppConfig.baseUrl}/work-orders/$workOrderId/signatures/$signatureId',
    ).replace(queryParameters: {'user_email': _email});

    final body = <String, dynamic>{'status': status};
    if (rejectionReason != null) body['rejection_reason'] = rejectionReason;

    final res = await http.patch(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );
    if (res.statusCode != 200) {
      final detail = _errorDetail(res, 'Failed to update signature');
      throw Exception(detail);
    }
  }

  Future<void> deleteSignature({
    required String workOrderId,
    required String signatureId,
  }) async {
    final uri = Uri.parse(
      '${AppConfig.baseUrl}/work-orders/$workOrderId/signatures/$signatureId',
    ).replace(queryParameters: {'user_email': _email});

    final res = await http.delete(uri);
    if (res.statusCode != 200) {
      final detail = _errorDetail(res, 'Failed to remove signature');
      throw Exception(detail);
    }
  }

  Future<Map<String, Map<String, dynamic>>> fetchBulkSignatureStatus(
      List<String> workOrderIds) async {
    if (workOrderIds.isEmpty) return {};

    final uri = Uri.parse('${AppConfig.baseUrl}/signatures/bulk').replace(
      queryParameters: {'work_order_ids': workOrderIds.join(',')},
    );

    final res = await http.get(uri);
    if (res.statusCode != 200) {
      throw Exception(_errorDetail(res, 'Failed to fetch signature statuses'));
    }

    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final statuses = (data['statuses'] as Map?) ?? {};
    return statuses.map((key, value) {
      return MapEntry(key.toString(), Map<String, dynamic>.from(value));
    });
  }

  Future<String?> fetchUserSignature(String userId) async {
    final uri = Uri.parse('${AppConfig.baseUrl}/users/$userId/signature')
        .replace(queryParameters: {'user_email': _email});
    final res = await http.get(uri);
    if (res.statusCode != 200) {
      throw Exception(_errorDetail(res, 'Failed to load saved signature'));
    }
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    return data['signature_path'] as String?;
  }

  Future<String?> saveUserSignature({
    required String userId,
    String? base64Data,
    Uint8List? fileBytes,
    String? fileName,
  }) async {
    if ((base64Data == null || base64Data.isEmpty) &&
        (fileBytes == null || fileBytes.isEmpty)) {
      throw Exception('Provide signature data or image bytes');
    }

    final uri = Uri.parse('${AppConfig.baseUrl}/users/$userId/signature');
    final request = http.MultipartRequest('POST', uri)
      ..fields['user_email'] = _email;

    if (base64Data != null && base64Data.isNotEmpty) {
      request.fields['signature_data'] = base64Data;
    }

    if (fileBytes != null && fileBytes.isNotEmpty) {
      request.files.add(http.MultipartFile.fromBytes(
        'file',
        fileBytes,
        filename: fileName ?? 'signature.png',
      ));
    }

    final streamed = await request.send();
    final res = await http.Response.fromStream(streamed);
    if (res.statusCode != 200) {
      throw Exception(_errorDetail(res, 'Failed to save saved signature'));
    }
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    return data['signature_path'] as String?;
  }

  Future<void> deleteUserSignature(String userId) async {
    final uri = Uri.parse('${AppConfig.baseUrl}/users/$userId/signature')
        .replace(queryParameters: {'user_email': _email});
    final res = await http.delete(uri);
    if (res.statusCode != 200) {
      throw Exception(_errorDetail(res, 'Failed to delete saved signature'));
    }
  }

  String _errorDetail(http.Response res, String fallback) {
    try {
      final body = jsonDecode(res.body);
      if (body is Map && body['detail'] is String) return body['detail'];
      return fallback;
    } catch (_) {
      return fallback;
    }
  }
}
