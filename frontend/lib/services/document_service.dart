import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import '../config.dart';

class DocumentService {
  final String _baseUrl = AppConfig.baseUrl;

  Future<Map<String, dynamic>> uploadDocument({
    required String filePath,
    required String fileName,
    required List<int> fileBytes,
    required String displayName,
    required String uploadedBy,
  }) async {
    final uri = Uri.parse('$_baseUrl/documents/upload');
    final request = http.MultipartRequest('POST', uri)
      ..fields['display_name'] = displayName
      ..fields['uploaded_by'] = uploadedBy
      ..files.add(http.MultipartFile.fromBytes(
        'file',
        fileBytes,
        filename: fileName,
        contentType: MediaType('application', 'pdf'),
      ));
    final streamed = await request.send();
    final body = await streamed.stream.bytesToString();
    if (streamed.statusCode != 200) {
      throw Exception('Upload failed: ${streamed.statusCode} $body');
    }
    return jsonDecode(body);
  }

  Future<List<Map<String, dynamic>>> listDocuments(String userEmail) async {
    final resp = await http.get(
      Uri.parse('$_baseUrl/documents/?user_email=$userEmail'),
    );
    if (resp.statusCode != 200)
      throw Exception('List failed: ${resp.statusCode}');
    return List<Map<String, dynamic>>.from(jsonDecode(resp.body));
  }

  Future<Map<String, dynamic>> getStatus(
      String documentId, String userEmail) async {
    final resp = await http.get(
      Uri.parse('$_baseUrl/documents/$documentId/status?user_email=$userEmail'),
    );
    if (resp.statusCode != 200)
      throw Exception('Status failed: ${resp.statusCode}');
    return jsonDecode(resp.body);
  }

  Future<void> deleteDocument(String documentId, String userEmail) async {
    final resp = await http.delete(
      Uri.parse('$_baseUrl/documents/$documentId?user_email=$userEmail'),
    );
    if (resp.statusCode != 200)
      throw Exception('Delete failed: ${resp.statusCode}');
  }

  Future<Map<String, dynamic>> reindexDocument(
      String documentId, String userEmail) async {
    final resp = await http.post(
      Uri.parse(
          '$_baseUrl/documents/$documentId/reindex?user_email=$userEmail'),
    );
    if (resp.statusCode != 200)
      throw Exception('Reindex failed: ${resp.statusCode}');
    return jsonDecode(resp.body);
  }

  Future<Map<String, dynamic>> listChunks(String documentId, String userEmail,
      {int page = 1, int pageSize = 20}) async {
    final resp = await http.get(
      Uri.parse(
          '$_baseUrl/documents/$documentId/chunks?user_email=$userEmail&page=$page&page_size=$pageSize'),
    );
    if (resp.statusCode != 200)
      throw Exception('List chunks failed: ${resp.statusCode}');
    return jsonDecode(resp.body);
  }

  Future<Map<String, dynamic>> getChunk(
      String documentId, String chunkId, String userEmail) async {
    final resp = await http.get(
      Uri.parse(
          '$_baseUrl/documents/$documentId/chunks/$chunkId?user_email=$userEmail'),
    );
    if (resp.statusCode != 200)
      throw Exception('Get chunk failed: ${resp.statusCode}');
    return jsonDecode(resp.body);
  }

  Future<Map<String, dynamic>> updateChunk(String documentId, String chunkId,
      String content, String userEmail) async {
    final resp = await http.put(
      Uri.parse('$_baseUrl/documents/$documentId/chunks/$chunkId'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'content': content, 'user_email': userEmail}),
    );
    if (resp.statusCode != 200)
      throw Exception('Update chunk failed: ${resp.statusCode}');
    return jsonDecode(resp.body);
  }

  Future<Map<String, dynamic>> addChunk(
      String documentId, String parentId, String content, String userEmail,
      {int? insertAfter}) async {
    final Map<String, dynamic> body = {
      'parent_id': parentId,
      'content': content,
      'user_email': userEmail,
    };
    if (insertAfter != null) body['insert_after'] = insertAfter;
    final resp = await http.post(
      Uri.parse('$_baseUrl/documents/$documentId/chunks'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );
    if (resp.statusCode != 200)
      throw Exception('Add chunk failed: ${resp.statusCode}');
    return jsonDecode(resp.body);
  }

  Future<void> deleteChunk(
      String documentId, String chunkId, String userEmail) async {
    final resp = await http.delete(
      Uri.parse(
          '$_baseUrl/documents/$documentId/chunks/$chunkId?user_email=$userEmail'),
    );
    if (resp.statusCode != 200)
      throw Exception('Delete chunk failed: ${resp.statusCode}');
  }

  Future<List<Map<String, dynamic>>> splitChunk(String documentId,
      String chunkId, int splitPosition, String userEmail) async {
    final resp = await http.post(
      Uri.parse(
          '$_baseUrl/documents/$documentId/chunks/$chunkId/split?split_position=$splitPosition&user_email=$userEmail'),
    );
    if (resp.statusCode != 200)
      throw Exception('Split chunk failed: ${resp.statusCode}');
    final data = jsonDecode(resp.body);
    return List<Map<String, dynamic>>.from(data['chunks'] ?? []);
  }

  Future<Map<String, dynamic>> mergeChunk(
      String documentId, String chunkId, String userEmail) async {
    final resp = await http.post(
      Uri.parse(
          '$_baseUrl/documents/$documentId/chunks/$chunkId/merge?user_email=$userEmail'),
    );
    if (resp.statusCode != 200)
      throw Exception('Merge chunk failed: ${resp.statusCode}');
    return jsonDecode(resp.body);
  }

  Future<void> reEmbedAll(String documentId, String userEmail) async {
    final resp = await http.post(
      Uri.parse(
          '$_baseUrl/documents/$documentId/chunks/re-embed?user_email=$userEmail'),
    );
    if (resp.statusCode != 200)
      throw Exception('Re-embed failed: ${resp.statusCode}');
  }

  Future<void> bulkDeleteChunks(
      String documentId, List<String> chunkIds, String userEmail) async {
    final encoded = jsonEncode(chunkIds);
    final resp = await http.delete(
      Uri.parse(
          '$_baseUrl/documents/$documentId/chunks/bulk-delete?chunk_ids=${Uri.encodeComponent(encoded)}&user_email=$userEmail'),
    );
    if (resp.statusCode != 200)
      throw Exception('Bulk delete failed: ${resp.statusCode}');
  }

}
