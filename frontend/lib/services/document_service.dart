import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/document.dart';
import '../config.dart';
import 'package:http/http.dart' as http;

class DocumentService {
  final SupabaseClient _client = Supabase.instance.client;

  Future<List<DocumentModel>> fetchDocuments() async {
    final response = await _client
        .from('documents')
        .select()
        .order('created_at', ascending: false);

    return (response as List)
        .map((doc) => DocumentModel.fromJson(doc))
        .toList();
  }

  Future<void> insertDocument({
    required String title,
    required String documentType,
    String? parsedText,
  }) async {
    await _client.from('documents').insert({
      'title': title,
      'document_type': documentType,
      'file_name': '',
      'file_extension': '',
      'mime_type': '',
      'file_path': '',
      'parsed_text': parsedText,
    });
  }

  /// ✅ FIXED: supports positional search
Future<List<DocumentModel>> searchDocuments(
  String? query, {
  String? documentType,
}) async {

  final searchQuery = query?.trim();

  var request = _client.from('documents').select();

  // Filter by document type
  if (documentType != null && documentType != "All") {
    request = request.eq('document_type', documentType);
  }

  final response = await request.order('created_at', ascending: false);

  final docs = (response as List)
      .map((doc) => DocumentModel.fromJson(doc))
      .toList();

  // Apply search locally (prevents duplicate API results)
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
  Future<void> deleteDocument(String id) async {
    final response = await http.delete(
      Uri.parse('${AppConfig.baseUrl}/delete/$id'),
    );

    if (response.statusCode != 200) {
      throw Exception("Failed to delete document");
    }
  }

  Future<void> deleteDocuments(List<String> ids) async {
    for (final id in ids) {
      await deleteDocument(id);
    }
  }

  Future<void> renameDocument(String id, String newTitle) async {
    await _client.from('documents').update({'title': newTitle}).eq('id', id);
  }

  Future<void> updateDocumentType(String id, String newType) async {
    await _client
        .from('documents')
        .update({'document_type': newType})
        .eq('id', id);
  }

  Future<List<DocumentModel>> filterByType(String type) async {
    final response =
        await _client.from('documents').select().eq('document_type', type);

    return (response as List)
        .map((doc) => DocumentModel.fromJson(doc))
        .toList();
  }
}
