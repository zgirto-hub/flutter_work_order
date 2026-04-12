import 'dart:async';
import 'dart:typed_data';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config.dart';
import '../models/manual.dart';
import '../models/manual_qa_answer.dart';

class ManualUploadException implements Exception {
  final String code;
  final String message;
  ManualUploadException(this.code, this.message);
  @override
  String toString() => message;
}

class ManualAskException implements Exception {
  final String code;
  final String message;
  ManualAskException(this.code, this.message);
  @override
  String toString() => message;
}

class ManualNotFoundException implements Exception {
  @override
  String toString() => 'Manual not found';
}

class ManualAssistantService {
  static MediaType? _getMediaType(String mimeType) {
    switch (mimeType) {
      case 'application/pdf':
        return MediaType('application', 'pdf');
      case 'text/plain':
        return MediaType('text', 'plain');
      case 'text/markdown':
        return MediaType('text', 'markdown');
      case 'application/vnd.openxmlformats-officedocument.wordprocessingml.document':
        return MediaType('application',
            'vnd.openxmlformats-officedocument.wordprocessingml.document');
      default:
        return null;
    }
  }

  Future<Map<String, dynamic>> getSettings() async {
    try {
      final res = await http.get(
        Uri.parse('${AppConfig.baseUrl}/manuals/settings'),
      );
      if (res.statusCode == 200) {
        return jsonDecode(res.body) as Map<String, dynamic>;
      }
      return {};
    } catch (e) {
      return {};
    }
  }

  Future<String> getDefaultModel() async {
    final settings = await getSettings();
    return settings['default_model'] as String? ?? '';
  }

  Future<String> getSystemInstructions() async {
    final settings = await getSettings();
    return settings['system_instructions'] as String? ?? '';
  }

  Future<String> updateSystemInstructions(String instructions) async {
    try {
      final res = await http.post(
        Uri.parse('${AppConfig.baseUrl}/manuals/settings'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'system_instructions': instructions}),
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        return data['system_instructions'] ?? instructions;
      }
      return instructions;
    } catch (e) {
      return instructions;
    }
  }

  Future<String> setDefaultModel(String modelName) async {
    try {
      final res = await http.post(
        Uri.parse('${AppConfig.baseUrl}/manuals/settings'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'default_model': modelName}),
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        return data['default_model'] ?? modelName;
      }
      return modelName;
    } catch (e) {
      return modelName;
    }
  }

  Future<Map<String, dynamic>> listManuals() async {
    try {
      final res = await http.get(
        Uri.parse('${AppConfig.baseUrl}/manuals/'),
        headers: {'Content-Type': 'application/json'},
      );

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final manuals = <Manual>[];
        for (var m in data['manuals'] ?? []) {
          manuals.add(Manual.fromJson(m));
        }
        final stats = CorpusStats.fromJson(data['corpus_stats'] ?? {});
        return {'manuals': manuals, 'corpus_stats': stats};
      } else {
        throw Exception('Failed to load manuals');
      }
    } catch (e) {
      rethrow;
    }
  }

  Future<Manual> uploadManual(
    String title,
    Uint8List fileBytes,
    String fileName,
    String mimeType, {
    required String userEmail,
  }) async {
    try {
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('${AppConfig.baseUrl}/manuals/upload'),
      );
      request.fields['title'] = title;
      request.fields['uploaded_by'] = userEmail;
      request.files.add(http.MultipartFile.fromBytes(
        'file',
        fileBytes,
        filename: fileName,
        contentType: _getMediaType(mimeType),
      ));

      final session = Supabase.instance.client.auth;
      final token = session.currentSession?.accessToken;
      if (token != null) {
        request.headers['Authorization'] = 'Bearer $token';
      }

      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return Manual.fromJson(data);
      } else if (response.statusCode == 413) {
        final data = jsonDecode(response.body);
        final errorCode = data['error'] ?? 'file_too_large';
        final message = data['message'] ?? 'File is too large';
        throw ManualUploadException(errorCode, message);
      } else if (response.statusCode == 415) {
        final data = jsonDecode(response.body);
        final errorCode = data['error'] ?? 'unsupported_media_type';
        final message = data['message'] ?? 'Unsupported file type';
        throw ManualUploadException(errorCode, message);
      } else if (response.statusCode == 422) {
        final data = jsonDecode(response.body);
        final errorCode = data['error'] ?? 'no_extractable_text';
        final message = data['message'] ?? 'No extractable text found';
        throw ManualUploadException(errorCode, message);
      } else if (response.statusCode == 504) {
        throw ManualUploadException('embedder_unavailable',
            'The embedding service is temporarily unavailable.');
      } else {
        throw ManualUploadException(
            'upload_failed', 'Something went wrong while uploading.');
      }
    } on ManualUploadException {
      rethrow;
    } catch (e) {
      throw ManualUploadException('upload_failed', e.toString());
    }
  }

  Future<List<Map<String, dynamic>>> listModels() async {
    try {
      final res = await http.get(
        Uri.parse('${AppConfig.baseUrl}/manuals/models'),
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final models = (data['models'] as List?)
                ?.map((m) => Map<String, dynamic>.from(m))
                .toList() ??
            [];
        return models;
      }
      return [];
    } catch (e) {
      return [];
    }
  }

  Future<ManualQaAnswer> askQuestion(
      String question, String? manualIdFilter,
      {required String userEmail,
      String? model,
      List<Map<String, String>>? history}) async {
    try {
      final body = <String, dynamic>{
        'question': question,
        'user_email': userEmail,
      };
      if (manualIdFilter != null) {
        body['manual_id'] = manualIdFilter;
      }
      if (model != null) {
        body['model'] = model;
      }
      if (history != null && history.isNotEmpty) {
        body['history'] = history;
      }

      final session = Supabase.instance.client.auth;
      final headers = <String, String>{
        'Content-Type': 'application/json',
      };
      final token = session.currentSession?.accessToken;
      if (token != null) {
        headers['Authorization'] = 'Bearer $token';
      }

      final res = await http.post(
        Uri.parse('${AppConfig.baseUrl}/manuals/ask'),
        headers: headers,
        body: jsonEncode(body),
      );

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        return ManualQaAnswer.fromJson(data);
      } else if (res.statusCode == 504) {
        throw ManualAskException('assistant_unavailable',
            'The assistant is taking longer than usual to respond.');
      } else if (res.statusCode == 400) {
        final data = jsonDecode(res.body);
        final errorCode = data['error'] ?? 'question_required';
        throw ManualAskException(
            errorCode, data['message'] ?? 'Question is required');
      } else {
        throw ManualAskException(
            'ask_failed', 'Something went wrong while answering.');
      }
    } on ManualAskException {
      rethrow;
    } catch (e) {
      throw ManualAskException('ask_failed', e.toString());
    }
  }

  Future<void> deleteManual(String manualId,
      {required String userEmail}) async {
    try {
      final res = await http.delete(
        Uri.parse(
            '${AppConfig.baseUrl}/manuals/$manualId?user_email=${Uri.encodeComponent(userEmail)}'),
      );

      if (res.statusCode == 204) {
        return;
      } else if (res.statusCode == 404) {
        throw ManualNotFoundException();
      } else {
        throw Exception('Failed to delete manual');
      }
    } catch (e) {
      if (e is ManualNotFoundException) rethrow;
      throw Exception('Failed to delete manual');
    }
  }
}
