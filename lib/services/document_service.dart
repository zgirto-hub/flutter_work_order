import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/document.dart';

class DocumentService {
  final SupabaseClient _client = Supabase.instance.client;

  Future<List<DocumentModel>> fetchDocuments() async {
    final response = await _client
        .from('documents')
        .select()
        .order('created_at', ascending: false);
    print("Supabase response: $response");
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

  Future<List<DocumentModel>> searchDocuments(String query) async {
    final response = await _client
        .from('documents')
        .select()
        .ilike('parsed_text', '%$query%');

    return (response as List)
        .map((doc) => DocumentModel.fromJson(doc))
        .toList();
  }
}
