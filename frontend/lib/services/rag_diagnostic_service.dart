import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config.dart';
import '../models/rag_diagnostic_entry.dart';

class RagDiagnosticService {
  String get _baseUrl => AppConfig.baseUrl;

  Map<String, String> _headers({String? idToken}) {
    final headers = <String, String>{'Content-Type': 'application/json'};
    final token = idToken ??
        Supabase.instance.client.auth.currentSession?.accessToken;
    if (token != null) headers['Authorization'] = 'Bearer $token';
    return headers;
  }

  Future<(List<RagDiagnosticEntry>, int)> fetchEntries({
    required String userEmail,
    String? source,
    String? decision,
    String? reasonCode,
    String? from,
    String? to,
    int limit = 50,
    int offset = 0,
  }) async {
    final params = <String, String>{
      'limit': limit.toString(),
      'offset': offset.toString(),
      'user_email': Uri.encodeComponent(userEmail),
    };
    if (source != null) params['source'] = source;
    if (decision != null) params['decision'] = decision;
    if (reasonCode != null) params['reason_code'] = reasonCode;
    if (from != null) params['from'] = from;
    if (to != null) params['to'] = to;

    final uri = Uri.parse('$_baseUrl/admin/rag-diagnostics').replace(queryParameters: params);
    final resp = await http.get(uri, headers: _headers());

    if (resp.statusCode == 403) throw Exception('Access denied. Admin role required.');
    if (resp.statusCode != 200) throw Exception('Failed to load diagnostics: ${resp.statusCode}');

    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    final entries = (data['entries'] as List)
        .map((e) => RagDiagnosticEntry.fromListJson(e as Map<String, dynamic>))
        .toList();
    final total = data['total'] as int;
    return (entries, total);
  }

  Future<RagDiagnosticEntry> fetchDetail(String id, {required String userEmail}) async {
    final uri = Uri.parse('$_baseUrl/admin/rag-diagnostics/$id').replace(queryParameters: {'user_email': Uri.encodeComponent(userEmail)});
    final resp = await http.get(uri, headers: _headers());

    if (resp.statusCode == 404) throw Exception('Diagnostic entry not found');
    if (resp.statusCode == 403) throw Exception('Access denied. Admin role required.');
    if (resp.statusCode != 200) throw Exception('Failed to load detail: ${resp.statusCode}');

    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    return RagDiagnosticEntry.fromDetailJson(data);
  }
}