import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config.dart';
import '../models/generated_letter.dart';

class LetterService {
  String get _email => Supabase.instance.client.auth.currentUser?.email ?? '';

  Future<Uint8List> regenerateV2(String letterId) async {
    final uri =
        Uri.parse('${AppConfig.baseUrl}/letters-v2/$letterId/regenerate');
    final res = await http.post(uri);
    if (res.statusCode != 200) {
      throw Exception('Failed to regenerate letter');
    }
    return res.bodyBytes;
  }

  Future<List<GeneratedLetter>> fetchAllV2() async {
    final uri = Uri.parse('${AppConfig.baseUrl}/letters-v2')
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

  Future<GeneratedLetter> fetchOneV2(String letterId) async {
    final uri = Uri.parse('${AppConfig.baseUrl}/letters-v2/$letterId');
    final res = await http.get(uri);
    if (res.statusCode != 200) {
      throw Exception('Failed to fetch letter');
    }
    return GeneratedLetter.fromJson(jsonDecode(res.body));
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

  Future<String> uploadImage(Uint8List bytes, String filename) async {
    final uri = Uri.parse('${AppConfig.baseUrl}/letters-v2/upload-image');
    final request = http.MultipartRequest('POST', uri);
    request.files
        .add(http.MultipartFile.fromBytes('file', bytes, filename: filename));
    final streamedRes = await request.send();
    final res = await http.Response.fromStream(streamedRes);
    if (res.statusCode != 200) {
      final errorBody = jsonDecode(res.body);
      throw Exception(errorBody['detail'] ?? 'Failed to upload image');
    }
    final response = jsonDecode(res.body);
    return response['url'];
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
