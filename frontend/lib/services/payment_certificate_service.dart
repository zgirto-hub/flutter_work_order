import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config.dart';
import '../models/payment_certificate.dart';

class PaymentCertificateService {
  String get _email =>
      Supabase.instance.client.auth.currentUser?.email ?? '';

  Future<({List<PaymentCertificate> items, int total})> fetchAll({
    int? limit,
    int offset = 0,
  }) async {
    final params = <String, String>{
      'email': _email,
      'offset': '$offset',
    };
    if (limit != null) params['limit'] = '$limit';

    final uri = Uri.parse('${AppConfig.baseUrl}/payment-certificates')
        .replace(queryParameters: params);
    final res = await http.get(uri);
    if (res.statusCode != 200) {
      throw Exception('Failed to fetch certificates');
    }
    final data = jsonDecode(res.body);
    final items = (data['certificates'] as List)
        .map((j) => PaymentCertificate.fromJson(j))
        .toList();
    final total = data['total'] as int? ?? items.length;
    return (items: items, total: total);
  }

  Future<PaymentCertificate> create(PaymentCertificate cert) async {
    final body = cert.toJson();
    body['created_by_email'] = _email;
    body['created_by'] = _email.split('@').first;

    final uri = Uri.parse('${AppConfig.baseUrl}/payment-certificates');
    final res = await http.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );
    if (res.statusCode != 200) {
      throw Exception('Failed to create certificate');
    }
    final data = jsonDecode(res.body);
    return PaymentCertificate.fromJson(data['certificate']);
  }

  Future<PaymentCertificate> update(
      String id, PaymentCertificate cert) async {
    final body = cert.toJson();
    body['created_by_email'] = cert.createdByEmail.isNotEmpty
        ? cert.createdByEmail
        : _email;
    body['created_by'] = cert.createdBy.isNotEmpty
        ? cert.createdBy
        : _email.split('@').first;

    final uri = Uri.parse(
            '${AppConfig.baseUrl}/payment-certificates/$id')
        .replace(queryParameters: {'user_email': _email});
    final res = await http.put(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );
    if (res.statusCode != 200) {
      throw Exception('Failed to update certificate');
    }
    final data = jsonDecode(res.body);
    return PaymentCertificate.fromJson(data['certificate']);
  }

  Future<void> delete(String id) async {
    final uri = Uri.parse(
            '${AppConfig.baseUrl}/payment-certificates/$id')
        .replace(queryParameters: {'user_email': _email});
    final res = await http.delete(uri);
    if (res.statusCode != 200) {
      throw Exception('Failed to delete certificate');
    }
  }

  /// Export a payment certificate as PDF. Returns raw PDF bytes.
  Future<Uint8List> exportPdf(String certId) async {
    final uri = Uri.parse(
        '${AppConfig.baseUrl}/payment-certificates/$certId/pdf');
    final res = await http.post(uri);
    if (res.statusCode != 200) {
      throw Exception('Failed to generate PDF');
    }
    return res.bodyBytes;
  }
}
