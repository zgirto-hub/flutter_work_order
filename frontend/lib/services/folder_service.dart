import 'dart:convert';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:http/http.dart' as http;
import '../models/folder_model.dart';
import '../config.dart';

class FolderService {
  final SupabaseClient _client = Supabase.instance.client;

  String get _email => _client.auth.currentUser?.email ?? '';

  // ---- Reads: via FastAPI (uses service-role key, bypasses RLS) ----

  Future<List<FolderModel>> fetchFolders({String? parentId}) async {
    final uri = parentId == null
        ? Uri.parse('${AppConfig.baseUrl}/folders?user_email=${Uri.encodeComponent(_email)}')
        : Uri.parse('${AppConfig.baseUrl}/folders?user_email=${Uri.encodeComponent(_email)}&parent_id=${Uri.encodeComponent(parentId)}');
    final response = await http.get(uri);
    if (response.statusCode != 200) throw Exception('Failed to fetch folders');
    final data = jsonDecode(response.body);
    return (data['folders'] as List).map((f) => FolderModel.fromJson(f)).toList();
  }

  /// Fetches every folder (all levels), sorted by name.
  Future<List<FolderModel>> fetchAllFolders() async {
    final response = await http.get(Uri.parse('${AppConfig.baseUrl}/folders/all'));
    if (response.statusCode != 200) throw Exception('Failed to fetch folders');
    final data = jsonDecode(response.body);
    return (data['folders'] as List).map((f) => FolderModel.fromJson(f)).toList();
  }

  // ---- Writes: via FastAPI ----

  Future<FolderModel> createFolder({
    required String name,
    String? parentId,
  }) async {
    final response = await http.post(
      Uri.parse('${AppConfig.baseUrl}/folders'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'name': name,
        'parent_id': parentId,
        'created_by': _email,
      }),
    );
    if (response.statusCode != 200) {
      throw Exception('Failed to create folder');
    }
    final data = jsonDecode(response.body);
    return FolderModel.fromJson(data['folder']);
  }

  Future<void> renameFolder(String id, String newName) async {
    final response = await http.patch(
      Uri.parse('${AppConfig.baseUrl}/folders/$id/rename?user_email=${Uri.encodeComponent(_email)}'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'name': newName}),
    );
    if (response.statusCode == 403) throw Exception('Not allowed to rename this folder');
    if (response.statusCode != 200) throw Exception('Failed to rename folder');
  }

  Future<void> deleteFolder(String id) async {
    final response = await http.delete(
      Uri.parse('${AppConfig.baseUrl}/folders/$id?user_email=${Uri.encodeComponent(_email)}'),
    );
    if (response.statusCode == 403) throw Exception('Not allowed to delete this folder');
    if (response.statusCode != 200) throw Exception('Failed to delete folder');
  }

  Future<void> moveFolder(String id, {String? newParentId}) async {
    final response = await http.patch(
      Uri.parse('${AppConfig.baseUrl}/folders/$id/move?user_email=${Uri.encodeComponent(_email)}'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'parent_id': newParentId}),
    );
    if (response.statusCode == 403) throw Exception('Not allowed to move this folder');
    if (response.statusCode != 200) throw Exception('Failed to move folder');
  }

  Future<void> moveDocument(String docId, {String? folderId}) async {
    final response = await http.patch(
      Uri.parse('${AppConfig.baseUrl}/documents/$docId/move?user_email=${Uri.encodeComponent(_email)}'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'folder_id': folderId}),
    );
    if (response.statusCode == 403) throw Exception('Not allowed to move this document');
    if (response.statusCode != 200) throw Exception('Failed to move document');
  }
}
