import 'dart:convert';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/file_model.dart';
import '../config.dart';
import 'package:http/http.dart' as http;

class FileService {
  final SupabaseClient _client = Supabase.instance.client;

  String get _baseUrl => AppConfig.baseUrl;

  Future<List<FileModel>> fetchFiles() async {
    final user = _client.auth.currentUser;
    final email = user?.email ?? '';

    final uri = Uri.parse('$_baseUrl/files/list?user_email=${Uri.encodeComponent(email)}');
    final response = await http.get(uri);

    if (response.statusCode != 200) {
      throw Exception('Failed to fetch files: ${response.statusCode}');
    }

    final data = jsonDecode(response.body);
    final files = (data['files'] as List)
        .map((doc) => FileModel.fromJson(doc))
        .toList();

    return files;
  }

  Future<FileModel> fetchFileById(String id) async {
    final user = _client.auth.currentUser;
    final email = user?.email ?? '';

    final uri = Uri.parse('$_baseUrl/files/$id?user_email=${Uri.encodeComponent(email)}');
    final response = await http.get(uri);

    if (response.statusCode == 403) {
      throw Exception('Access denied');
    }
    if (response.statusCode != 200) {
      throw Exception('Failed to fetch file: ${response.statusCode}');
    }

    final data = jsonDecode(response.body);
    return FileModel.fromJson(data['file']);
  }

  Future<void> insertFile({
    required String title,
    required String fileType,
    String? parsedText,
    bool isPrivate = false,
  }) async {
    final user = _client.auth.currentUser;
    final email = user?.email;

    await _client.from('files').insert({
      'title': title,
      'file_type': fileType,
      'file_name': '',
      'file_extension': '',
      'mime_type': '',
      'file_path': '',
      'parsed_text': parsedText,
      'uploaded_by': email,
      'is_private': isPrivate,
    });
  }

  Future<List<FileModel>> searchFiles(
    String? query, {
    String? fileType,
  }) async {
    final searchQuery = query?.trim();

    var request = _client.from('files').select();

    if (fileType != null && fileType != "All") {
      request = request.eq('file_type', fileType);
    }

    final response = await request.order('created_at', ascending: false);

    final docs = (response as List)
        .map((doc) => FileModel.fromJson(doc))
        .toList();

    if (searchQuery != null && searchQuery.isNotEmpty) {
      return docs.where((doc) {
        final title = doc.title.toLowerCase();
        final parsed = (doc.parsedText ?? "").toLowerCase();
        final q = searchQuery.toLowerCase();
        return title.contains(q) || parsed.contains(q);
      }).toList();
    }

    return docs;
  }

  Future<void> deleteFile(String id) async {
    final user = _client.auth.currentUser;
    final email = user?.email ?? "";

    final response = await http.delete(
      Uri.parse('${AppConfig.baseUrl}/delete/$id?user_email=$email'),
    );

    if (response.statusCode == 403) {
      throw Exception("You cannot delete this file");
    }

    if (response.statusCode != 200) {
      throw Exception("Failed to delete file");
    }
  }

  Future<void> deleteFiles(List<String> ids) async {
    for (final id in ids) {
      await deleteFile(id);
    }
  }

  Future<void> renameFile(String id, String newTitle) async {
    await _client.from('files').update({'title': newTitle}).eq('id', id);
  }

  Future<void> updateFileType(String id, String newType) async {
    await _client
        .from('files')
        .update({'file_type': newType})
        .eq('id', id);
  }

  Future<void> updateExpirationDate(String id, DateTime? date) async {
    await _client.from('files').update({
      'expiration_date': date?.toIso8601String(),
    }).eq('id', id);
  }

  Future<void> updateFileDepartment(String fileId, String? departmentId) async {
    final user = _client.auth.currentUser;
    final email = user?.email ?? '';

    final uri = Uri.parse('$_baseUrl/files/$fileId/department?user_email=${Uri.encodeComponent(email)}');
    final response = await http.patch(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'department_id': departmentId}),
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to update department: ${response.statusCode}');
    }
  }

  Future<List<FileModel>> filterByType(String type) async {
    final response =
        await _client.from('files').select().eq('file_type', type);

    return (response as List)
        .map((doc) => FileModel.fromJson(doc))
        .toList();
  }
}