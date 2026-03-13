import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/document.dart';
import '../config.dart';
import 'package:http/http.dart' as http;

class DocumentService {
  final SupabaseClient _client = Supabase.instance.client;

Future<List<DocumentModel>> fetchDocuments() async {

  final user = _client.auth.currentUser;
  final email = user?.email ?? "";

final shared = await _client
    .from('document_permissions')
    .select('document_id,user_email');

final sharedIds = (shared as List)
    .where((row) => row['user_email'] == email)
    .map((row) => row['document_id'].toString())
    .toList();

print("SHARED IDS: $sharedIds");

  String filter;

  if (sharedIds.isEmpty) {
    filter = 'is_private.eq.false,uploaded_by.eq.$email';
  } else {
    filter =
        'is_private.eq.false,uploaded_by.eq.$email,id.in.(${sharedIds.join(',')})';
  }

  final response = await _client
      .from('documents')
      .select()
      .or(filter)
      .order('created_at', ascending: false);

  final docs = (response as List)
      .map((doc) => DocumentModel.fromJson(doc))
      .toList();

  /// Mark shared documents
  final result = docs.map((doc) {
    if (sharedIds.contains(doc.id)) {
      return doc.copyWith(isShared: true);
    }
    return doc;
  }).toList();

  return result;
}

  Future<void> insertDocument({
  required String title,
  required String documentType,
  String? parsedText,
  bool isPrivate = false,
}) async {

  final user = _client.auth.currentUser;
  final email = user?.email;

  await _client.from('documents').insert({
    'title': title,
    'document_type': documentType,
    'file_name': '',
    'file_extension': '',
    'mime_type': '',
    'file_path': '',
    'parsed_text': parsedText,
    'uploaded_by': email,
    'is_private': isPrivate,
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

  final user = _client.auth.currentUser;
  final email = user?.email ?? "";

  final response = await http.delete(
    Uri.parse('${AppConfig.baseUrl}/delete/$id?user_email=$email'),
  );

  if (response.statusCode == 403) {
    throw Exception("You cannot delete this document");
  }

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
