import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/work_order_signature.dart';
import '../config.dart';

class SignatureService {
  String get _email =>
      Supabase.instance.client.auth.currentUser?.email ?? '';

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
    required String signatureData,
  }) async {
    final res = await http.post(
      Uri.parse('${AppConfig.baseUrl}/work-orders/$workOrderId/signatures'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'signer_email': signerEmail,
        'signer_role': signerRole,
        'signature_data': signatureData,
      }),
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
