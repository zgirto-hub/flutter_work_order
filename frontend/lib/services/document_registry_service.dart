import 'dart:convert';
import 'package:file_picker/file_picker.dart';
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
    bool replied = false,
  }) async {
    final response = await http.post(
      Uri.parse('${AppConfig.baseUrl}/document-registry'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'document_name': documentName,
        'document_number': documentNumber,
        'date': date,
        'replied': replied,
        'created_by': _email,
      }),
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to create entry');
    }
  }

  Future<void> updateEntry(
    String id, {
    required String documentName,
    required String documentNumber,
    required String date,
    bool replied = false,
  }) async {
    final response = await http.put(
      Uri.parse('${AppConfig.baseUrl}/document-registry/$id'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'document_name': documentName,
        'document_number': documentNumber,
        'date': date,
        'replied': replied,
        'user_email': _email,
      }),
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to update entry');
    }
  }

  Future<PlatformFile?> pickAttachment() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'doc', 'docx', 'jpg', 'jpeg', 'png', 'gif'],
      withData: true,
    );
    return result?.files.isNotEmpty == true ? result!.files.first : null;
  }

  Future<bool> uploadAttachment(String entryId, PlatformFile file) async {
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('${AppConfig.baseUrl}/document-registry/$entryId/attachment'),
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
    }

    final streamedResponse = await request.send();
    return streamedResponse.statusCode == 200;
  }

  Future<void> deleteAttachment(String entryId) async {
    final response = await http.delete(
      Uri.parse(
        '${AppConfig.baseUrl}/document-registry/$entryId/attachment?user_email=${Uri.encodeComponent(_email)}',
      ),
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to delete attachment');
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
