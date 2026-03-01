import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/document.dart';

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
}