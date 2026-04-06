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
  Future<Uint8List> generateV2(Map<String, dynamic> body) async {
    body['created_by_email'] = _email;
    final uri = Uri.parse('${AppConfig.baseUrl}/letters-v2/generate');
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
}
