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
      Uri.parse(
          '$_baseUrl/documents/$documentId/status?user_email=$userEmail'),
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
}
