import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config.dart';
import '../models/generated_letter.dart';

class LetterService {
  String get _email => Supabase.instance.client.auth.currentUser?.email ?? '';

  Future<List<GeneratedLetter>> fetchAll() async {
    final uri = Uri.parse('${AppConfig.baseUrl}/letters')
        .replace(queryParameters: {'email': _email});
    final res = await http.get(uri);
    if (res.statusCode != 200) {
      throw Exception('Failed to fetch letters');
    }
    final data = jsonDecode(res.body);
    final letters = (data['letters'] as List)
        .map((j) => GeneratedLetter.fromJson(j))
        .toList();
    return letters;
  }

  Future<Uint8List> generate(GeneratedLetter letter) async {
    final body = letter.toJson();
    body['created_by_email'] = _email;

    final uri = Uri.parse('${AppConfig.baseUrl}/letters/generate');
    final res = await http.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );
    if (res.statusCode != 200) {
      throw Exception('Failed to generate letter');
    }
    return res.bodyBytes;
  }

  Future<Uint8List> regenerate(String letterId) async {
    final uri = Uri.parse('${AppConfig.baseUrl}/letters/$letterId/regenerate');
    final res = await http.post(uri);
    if (res.statusCode != 200) {
      throw Exception('Failed to regenerate letter');
    }
    return res.bodyBytes;
  }

  /// V2 endpoint — sends raw map with body_html for WeasyPrint rendering.
  Future<Uint8List> generateV2(Map<String, dynamic> body,
      {List<String> paymentCertificateIds = const [],
      bool forceReassign = false}) async {
    body['created_by_email'] = _email;
    body['payment_certificate_ids'] = paymentCertificateIds;
    body['force_reassign'] = forceReassign;
    final uri = Uri.parse('${AppConfig.baseUrl}/letters-v2/generate');
    final res = await http.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );
    if (res.statusCode == 409) {
      final errorBody = jsonDecode(res.body);
      if (errorBody['error'] == 'certificates_already_linked') {
        throw CertificatesAlreadyLinkedException(
            ((errorBody['conflicts'] ?? []) as List)
                .map((c) => Map<String, dynamic>.from(c as Map))
                .toList());
      }
    }
    if (res.statusCode != 200) {
      throw Exception('Failed to generate letter');
    }
    return res.bodyBytes;
  }

  /// Update an existing letter record and regenerate PDF.
  Future<Uint8List> update(String letterId, GeneratedLetter letter) async {
    final body = letter.toJson();
    body['created_by_email'] = _email;
    final uri = Uri.parse('${AppConfig.baseUrl}/letters/$letterId');
    final res = await http.put(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );
    if (res.statusCode != 200) {
      throw Exception('Failed to update letter');
    }
    return res.bodyBytes;
  }

  /// V2 update — updates existing letter record with rich HTML body.
  Future<Uint8List> updateV2(String letterId, Map<String, dynamic> body,
      {List<String> paymentCertificateIds = const [],
      bool forceReassign = false}) async {
    body['created_by_email'] = _email;
    body['payment_certificate_ids'] = paymentCertificateIds;
    body['force_reassign'] = forceReassign;
    final uri = Uri.parse('${AppConfig.baseUrl}/letters-v2/$letterId');
    final res = await http.put(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );
    if (res.statusCode == 409) {
      final errorBody = jsonDecode(res.body);
      if (errorBody['error'] == 'certificates_already_linked') {
        throw CertificatesAlreadyLinkedException(
            ((errorBody['conflicts'] ?? []) as List)
                .map((c) => Map<String, dynamic>.from(c as Map))
                .toList());
      }
    }
    if (res.statusCode != 200) {
      throw Exception('Failed to update letter');
    }
    return res.bodyBytes;
  }

  Future<void> delete(String letterId) async {
    final uri = Uri.parse('${AppConfig.baseUrl}/letters-v2/$letterId');
    final res = await http.delete(uri);
    if (res.statusCode != 200) {
      throw Exception('Failed to delete letter');
    }
  }

  Future<void> linkPaymentCertificate(String certId, String letterId) async {
    final uri = Uri.parse(
        '${AppConfig.baseUrl}/payment-certificates/$certId/link-letter');
    final res = await http.patch(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'letter_id': letterId}),
    );
    if (res.statusCode != 200) {
      throw Exception('Failed to link payment certificate');
    }
  }

  Future<Uint8List> exportLetterWithAttachments({
    required String letterId,
    required Map<String, dynamic> letterBody,
    required List<String> orderedCertIds,
    required Map<String, Uint8List> certPdfs,
    required String requesterEmail,
  }) async {
    final uri = Uri.parse(
        '${AppConfig.baseUrl}/letters-v2/$letterId/export-with-attachments');
    final request = http.MultipartRequest('POST', uri);
    request.fields['letter_body'] = jsonEncode(letterBody);
    request.fields['order'] = jsonEncode(orderedCertIds);
    request.fields['requester_email'] = requesterEmail;
    for (final entry in certPdfs.entries) {
      request.files.add(http.MultipartFile.fromBytes(
        'files',
        entry.value,
        filename: entry.key,
      ));
    }
    final streamedRes = await request.send();
    final res = await http.Response.fromStream(streamedRes);
    if (res.statusCode != 200) {
      throw Exception('Failed to export letter with attachments');
    }
    return res.bodyBytes;
  }
}

class CertificatesAlreadyLinkedException implements Exception {
  final List<Map<String, dynamic>> conflicts;
  CertificatesAlreadyLinkedException(this.conflicts);
  @override
  String toString() =>
      'CertificatesAlreadyLinkedException(${conflicts.length} conflicts)';
}
