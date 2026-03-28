import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config.dart';
import '../models/registry_entry.dart';

class DocumentRegistryService {
  String get _email =>
      Supabase.instance.client.auth.currentUser?.email ?? '';

  Future<List<RegistryEntry>> fetchEntries({String? search}) async {
    final params = <String, String>{};
    if (search != null && search.trim().isNotEmpty) {
      params['search'] = search.trim();
    }

    final uri = Uri.parse('${AppConfig.baseUrl}/document-registry')
        .replace(queryParameters: params.isNotEmpty ? params : null);

    final response = await http.get(uri);

    if (response.statusCode != 200) {
      throw Exception('Failed to load entries');
    }

    final data = jsonDecode(response.body);
    final list = data['entries'] as List;
    return list.map((e) => RegistryEntry.fromJson(e)).toList();
  }

  Future<void> createEntry({
    required String documentName,
    required String documentNumber,
    required String date,
  }) async {
    final response = await http.post(
      Uri.parse('${AppConfig.baseUrl}/document-registry'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'document_name': documentName,
        'document_number': documentNumber,
        'date': date,
        'created_by': _email,
      }),
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to create entry');
    }
  }

  Future<void> deleteEntry(String id) async {
    final response = await http.delete(
      Uri.parse(
        '${AppConfig.baseUrl}/document-registry/$id?user_email=${Uri.encodeComponent(_email)}',
      ),
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to delete entry');
    }
  }
}
