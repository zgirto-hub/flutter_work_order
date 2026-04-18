import 'dart:async';
import 'dart:typed_data';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config.dart';
import '../models/manual.dart';
import '../models/manual_qa_answer.dart';

class SseEvent {
  final String? token;
  final Map<String, dynamic>? metadata;
  final String? error;
  SseEvent.token(this.token)
      : metadata = null,
        error = null;
  SseEvent.metadata(this.metadata)
      : token = null,
        error = null;
  SseEvent.error(this.error)
      : token = null,
        metadata = null;
}

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

  Future<ManualQaAnswer> askQuestion(String question, String? manualIdFilter,
      {required String userEmail,
      String? model,
      List<Map<String, String>>? history,
      String? sessionSummary}) async {
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
      if (sessionSummary != null) {
        body['session_summary'] = sessionSummary;
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

  Stream<SseEvent> askQuestionStream(String question, String? manualIdFilter,
      {required String userEmail,
      String? model,
      List<Map<String, String>>? history,
      String? sessionSummary}) {
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
    if (sessionSummary != null) {
      body['session_summary'] = sessionSummary;
    }

    final session = Supabase.instance.client.auth;
    final headers = <String, String>{
      'Content-Type': 'application/json',
    };
    final token = session.currentSession?.accessToken;
    if (token != null) {
      headers['Authorization'] = 'Bearer $token';
    }

    _activeStreamClient = http.Client();
    final uri = Uri.parse('${AppConfig.baseUrl}/manuals/ask/stream');
    final request = http.Request('POST', uri);
    request.headers.addAll(headers);
    request.body = jsonEncode(body);

    final controller = StreamController<SseEvent>();

    _activeStreamClient!.send(request).then((response) {
      if (response.statusCode != 200) {
        controller.add(SseEvent.error('HTTP ${response.statusCode}'));
        controller.close();
        _activeStreamClient?.close();
        _activeStreamClient = null;
        return;
      }

      String eventType = 'message';

      response.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(
        (line) {
          if (line.startsWith('event: ')) {
            eventType = line.substring(7).trim();
          } else if (line.startsWith('data:')) {
            // Preserve leading whitespace in token data (I4 fix).
            // Strip exactly "data:" prefix (5 chars), then remove the single
            // space that sse-starlette adds per SSE convention.
            var data = line.substring(5);
            if (data.startsWith(' ')) {
              data = data.substring(1);
            }
            if (eventType == 'metadata') {
              try {
                final metadata = jsonDecode(data) as Map<String, dynamic>;
                controller.add(SseEvent.metadata(metadata));
              } catch (e) {
                controller.add(SseEvent.error('Failed to parse metadata'));
              }
            } else if (eventType == 'error') {
              try {
                final error = jsonDecode(data) as Map<String, dynamic>;
                controller
                    .add(SseEvent.error(error['message'] ?? 'Unknown error'));
              } catch (e) {
                controller.add(SseEvent.error(data));
              }
            } else {
              if (data.isNotEmpty) {
                controller.add(SseEvent.token(data));
              }
            }
            eventType = 'message';
          } else if (line.isEmpty) {
            eventType = 'message';
          }
        },
        onError: (e) {
          if (!controller.isClosed) {
            controller.add(SseEvent.error('Connection lost'));
            controller.close();
          }
          _activeStreamClient?.close();
          _activeStreamClient = null;
        },
        onDone: () {
          if (!controller.isClosed) {
            controller.close();
          }
          _activeStreamClient?.close();
          _activeStreamClient = null;
        },
      );
    }).catchError((e) {
      if (!controller.isClosed) {
        controller.add(SseEvent.error('Connection failed: $e'));
        controller.close();
      }
      _activeStreamClient?.close();
      _activeStreamClient = null;
    });

    return controller.stream;
  }

  http.Client? _activeStreamClient;

  void cancelStream() {
    _activeStreamClient?.close();
    _activeStreamClient = null;
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

  Future<String> rateAnswer({
    required String questionText,
    required String answerText,
    required List<Map<String, dynamic>> sourceChunks,
    required String rating,
    required String raterEmail,
    String? manualId,
    String? modelUsed,
    String? validatedQaId,
    String? sessionSummary,
  }) async {
    try {
      final body = <String, dynamic>{
        'question_text': questionText,
        'answer_text': answerText,
        'source_chunks': sourceChunks,
        'rating': rating,
        'rater_email': raterEmail,
      };
      if (manualId != null) body['manual_id'] = manualId;
      if (modelUsed != null) body['model_used'] = modelUsed;
      if (validatedQaId != null) body['validated_qa_id'] = validatedQaId;
      if (sessionSummary != null) body['session_summary'] = sessionSummary;

      final session = Supabase.instance.client.auth;
      final headers = <String, String>{'Content-Type': 'application/json'};
      final token = session.currentSession?.accessToken;
      if (token != null) headers['Authorization'] = 'Bearer $token';

      final res = await http.post(
        Uri.parse('${AppConfig.baseUrl}/manuals/rate-answer'),
        headers: headers,
        body: jsonEncode(body),
      );

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        return data['id'] as String;
      } else {
        throw Exception('Failed to rate answer');
      }
    } catch (e) {
      throw Exception('Failed to rate answer: $e');
    }
  }

  Future<List<Map<String, dynamic>>> getFlaggedAnswers(
      {required String userEmail}) async {
    try {
      final session = Supabase.instance.client.auth;
      final headers = <String, String>{};
      final token = session.currentSession?.accessToken;
      if (token != null) headers['Authorization'] = 'Bearer $token';

      final res = await http.get(
        Uri.parse(
            '${AppConfig.baseUrl}/manuals/flagged-answers?user_email=${Uri.encodeComponent(userEmail)}'),
        headers: headers,
      );

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        return List<Map<String, dynamic>>.from(data['items'] ?? []);
      } else if (res.statusCode == 403) {
        throw Exception('Admin access required');
      } else {
        throw Exception('Failed to get flagged answers');
      }
    } catch (e) {
      rethrow;
    }
  }

  Future<Map<String, dynamic>> reviewAnswer({
    required String ratingId,
    required String action,
    String? correctedAnswer,
    required String reviewerEmail,
  }) async {
    try {
      final body = <String, dynamic>{
        'rating_id': ratingId,
        'action': action,
        'reviewer_email': reviewerEmail,
      };
      if (correctedAnswer != null) body['corrected_answer'] = correctedAnswer;

      final session = Supabase.instance.client.auth;
      final headers = <String, String>{'Content-Type': 'application/json'};
      final token = session.currentSession?.accessToken;
      if (token != null) headers['Authorization'] = 'Bearer $token';

      final res = await http.post(
        Uri.parse('${AppConfig.baseUrl}/manuals/review-answer'),
        headers: headers,
        body: jsonEncode(body),
      );

      if (res.statusCode == 200) {
        return jsonDecode(res.body) as Map<String, dynamic>;
      } else if (res.statusCode == 403) {
        throw Exception('Admin access required');
      } else {
        throw Exception('Failed to review answer');
      }
    } catch (e) {
      rethrow;
    }
  }

  /// Returns the paraphrase variants. If the backend generation failed but
  /// returned 200 with an empty list + error message, throws with that
  /// message so callers can surface the real reason. Non-2xx responses
  /// also throw with parsed detail.
  Future<List<String>> generateParaphraseVariants({
    required String questionText,
    required String userEmail,
    String? ratingId,
    String lang = 'en',
  }) async {
    final session = Supabase.instance.client.auth;
    final headers = <String, String>{'Content-Type': 'application/json'};
    final token = session.currentSession?.accessToken;
    if (token != null) headers['Authorization'] = 'Bearer $token';

    final res = await http.post(
      Uri.parse(
          '${AppConfig.baseUrl}/manuals/paraphrase-variants?user_email=${Uri.encodeComponent(userEmail)}'),
      headers: headers,
      body: jsonEncode({
        'question_text': questionText,
        if (ratingId != null) 'rating_id': ratingId,
        'lang': lang,
      }),
    );

    if (res.statusCode == 200) {
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final variants = (data['variants'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [];
      // Backend returns {variants: [], error: "..."} when AI provider failed
      // after retry. Surface the reason instead of silently returning empty.
      if (variants.isEmpty && data['error'] != null) {
        throw Exception(data['error'].toString());
      }
      return variants;
    } else if (res.statusCode == 403) {
      throw Exception('Admin access required');
    } else {
      String detail = 'HTTP ${res.statusCode}';
      try {
        final body = jsonDecode(res.body);
        if (body is Map) {
          final d = body['detail'];
          detail = d is Map ? (d['message'] ?? d['error'] ?? d.toString()) : (d?.toString() ?? body.toString());
        }
      } catch (_) {
        if (res.body.isNotEmpty) detail = res.body.substring(0, res.body.length.clamp(0, 200));
      }
      throw Exception('Failed to generate variants: $detail');
    }
  }

  Future<Map<String, dynamic>> reviewAnswerWithVariants({
    required String ratingId,
    required String action,
    required String userEmail,
    String? correctedAnswer,
    String? existingValidatedQaId,
    required List<String> variants,
  }) async {
    final body = <String, dynamic>{
      'rating_id': ratingId,
      'action': action,
      'variants': variants,
    };
    if (correctedAnswer != null) body['corrected_answer'] = correctedAnswer;
    if (existingValidatedQaId != null) {
      body['existing_validated_qa_id'] = existingValidatedQaId;
    }

    final session = Supabase.instance.client.auth;
    final headers = <String, String>{'Content-Type': 'application/json'};
    final token = session.currentSession?.accessToken;
    if (token != null) headers['Authorization'] = 'Bearer $token';

    final res = await http.post(
      Uri.parse(
          '${AppConfig.baseUrl}/manuals/review-answer-with-variants?user_email=${Uri.encodeComponent(userEmail)}'),
      headers: headers,
      body: jsonEncode(body),
    );

    if (res.statusCode == 200) {
      return jsonDecode(res.body) as Map<String, dynamic>;
    } else if (res.statusCode == 403) {
      throw Exception('Admin access required');
    } else if (res.statusCode == 400) {
      final err = jsonDecode(res.body);
      final detail = err['detail'];
      final msg = detail is Map ? (detail['message'] ?? detail['error'] ?? detail.toString()) : detail?.toString();
      throw Exception(msg ?? 'Invalid request');
    } else if (res.statusCode == 404) {
      throw Exception('Rating not found');
    } else {
      String detail = 'HTTP ${res.statusCode}';
      try {
        final body = jsonDecode(res.body);
        if (body is Map) {
          final d = body['detail'];
          detail = d is Map ? (d['message'] ?? d['error'] ?? d.toString()) : (d?.toString() ?? body.toString());
        }
      } catch (_) {
        if (res.body.isNotEmpty) detail = res.body.substring(0, res.body.length.clamp(0, 200));
      }
      throw Exception('Failed to review answer: $detail');
    }
  }

  Future<Map<String, dynamic>> listChunks(String manualId,
      {int page = 1, int pageSize = 20, required String userEmail}) async {
    try {
      final res = await http.get(
        Uri.parse(
            '${AppConfig.baseUrl}/manuals/$manualId/chunks?page=$page&page_size=$pageSize&user_email=${Uri.encodeComponent(userEmail)}'),
      );
      if (res.statusCode == 200) return jsonDecode(res.body);
      if (res.statusCode == 403) throw Exception('Admin access required');
      throw Exception('Failed to load chunks');
    } catch (e) {
      rethrow;
    }
  }

  Future<Map<String, dynamic>> getChunk(String manualId, String chunkId,
      {required String userEmail}) async {
    try {
      final res = await http.get(
        Uri.parse(
            '${AppConfig.baseUrl}/manuals/$manualId/chunks/$chunkId?user_email=${Uri.encodeComponent(userEmail)}'),
      );
      if (res.statusCode == 200) return jsonDecode(res.body);
      if (res.statusCode == 403) throw Exception('Admin access required');
      throw Exception('Failed to load chunk');
    } catch (e) {
      rethrow;
    }
  }

  Future<Map<String, dynamic>> updateChunk(
      String manualId, String chunkId, String content,
      {required String userEmail}) async {
    try {
      final res = await http.put(
        Uri.parse('${AppConfig.baseUrl}/manuals/$manualId/chunks/$chunkId'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'content': content, 'user_email': userEmail}),
      );
      if (res.statusCode == 200) return jsonDecode(res.body);
      if (res.statusCode == 403) throw Exception('Admin access required');
      throw Exception('Failed to update chunk');
    } catch (e) {
      rethrow;
    }
  }

  Future<void> deleteChunk(String manualId, String chunkId,
      {required String userEmail}) async {
    try {
      final res = await http.delete(
        Uri.parse(
            '${AppConfig.baseUrl}/manuals/$manualId/chunks/$chunkId?user_email=${Uri.encodeComponent(userEmail)}'),
      );
      if (res.statusCode == 204) return;
      if (res.statusCode == 403) throw Exception('Admin access required');
      throw Exception('Failed to delete chunk');
    } catch (e) {
      rethrow;
    }
  }

  Future<Map<String, dynamic>> addChunk(String manualId, String content,
      {int insertAfter = -1, required String userEmail}) async {
    try {
      final res = await http.post(
        Uri.parse('${AppConfig.baseUrl}/manuals/$manualId/chunks'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'content': content,
          'insert_after': insertAfter,
          'user_email': userEmail
        }),
      );
      if (res.statusCode == 200) return jsonDecode(res.body);
      if (res.statusCode == 403) throw Exception('Admin access required');
      throw Exception('Failed to add chunk');
    } catch (e) {
      rethrow;
    }
  }

  Future<Map<String, dynamic>> splitChunk(
      String manualId, String chunkId, int splitPosition,
      {required String userEmail}) async {
    try {
      final res = await http.post(
        Uri.parse(
            '${AppConfig.baseUrl}/manuals/$manualId/chunks/$chunkId/split'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(
            {'split_position': splitPosition, 'user_email': userEmail}),
      );
      if (res.statusCode == 200) return jsonDecode(res.body);
      if (res.statusCode == 403) throw Exception('Admin access required');
      throw Exception('Failed to split chunk');
    } catch (e) {
      rethrow;
    }
  }

  Future<Map<String, dynamic>> mergeChunk(String manualId, String chunkId,
      {required String userEmail}) async {
    try {
      final res = await http.post(
        Uri.parse(
            '${AppConfig.baseUrl}/manuals/$manualId/chunks/$chunkId/merge'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'user_email': userEmail}),
      );
      if (res.statusCode == 200) return jsonDecode(res.body);
      if (res.statusCode == 403) throw Exception('Admin access required');
      throw Exception('Failed to merge chunk');
    } catch (e) {
      rethrow;
    }
  }

  Future<Map<String, dynamic>> reEmbedAll(String manualId,
      {required String userEmail}) async {
    try {
      final res = await http.post(
        Uri.parse(
            '${AppConfig.baseUrl}/manuals/$manualId/chunks/re-embed?user_email=${Uri.encodeComponent(userEmail)}'),
      );
      if (res.statusCode == 200) return jsonDecode(res.body);
      if (res.statusCode == 403) throw Exception('Admin access required');
      throw Exception('Failed to start re-embed');
    } catch (e) {
      rethrow;
    }
  }

  Future<Map<String, dynamic>> bulkDeleteChunks(
      String manualId, List<String> chunkIds,
      {required String userEmail}) async {
    try {
      final request = http.Request(
        'DELETE',
        Uri.parse('${AppConfig.baseUrl}/manuals/$manualId/chunks/bulk-delete'),
      );
      request.headers['Content-Type'] = 'application/json';
      request.body =
          jsonEncode({'chunk_ids': chunkIds, 'user_email': userEmail});

      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) return jsonDecode(response.body);
      if (response.statusCode == 403) throw Exception('Admin access required');
      throw Exception('Failed to bulk delete chunks');
    } catch (e) {
      rethrow;
    }
  }

  Future<Map<String, dynamic>> getVerifiedAnswers({
    required String userEmail,
    String? search,
    int limit = 50,
    int offset = 0,
    String sort = 'recent',
  }) async {
    try {
      final session = Supabase.instance.client.auth;
      final headers = <String, String>{};
      final token = session.currentSession?.accessToken;
      if (token != null) headers['Authorization'] = 'Bearer $token';

      var url =
          '${AppConfig.baseUrl}/manuals/verified-answers?user_email=${Uri.encodeComponent(userEmail)}&limit=$limit&offset=$offset&sort=${Uri.encodeComponent(sort)}';
      if (search != null && search.isNotEmpty) {
        url += '&search=${Uri.encodeComponent(search)}';
      }

      final res = await http.get(
        Uri.parse(url),
        headers: headers,
      );

      if (res.statusCode == 200) {
        return jsonDecode(res.body) as Map<String, dynamic>;
      } else if (res.statusCode == 403) {
        throw Exception('Admin access required');
      } else {
        throw Exception('Failed to get verified answers');
      }
    } catch (e) {
      rethrow;
    }
  }

  Future<Map<String, dynamic>> updateVerifiedAnswer({
    required String qaId,
    String? questionText,
    String? validatedAnswer,
    required String editorEmail,
  }) async {
    try {
      final body = <String, dynamic>{'editor_email': editorEmail};
      if (questionText != null) body['question_text'] = questionText;
      if (validatedAnswer != null) body['validated_answer'] = validatedAnswer;

      final session = Supabase.instance.client.auth;
      final headers = <String, String>{'Content-Type': 'application/json'};
      final token = session.currentSession?.accessToken;
      if (token != null) headers['Authorization'] = 'Bearer $token';

      final res = await http.put(
        Uri.parse('${AppConfig.baseUrl}/manuals/verified-answers/$qaId'),
        headers: headers,
        body: jsonEncode(body),
      );

      if (res.statusCode == 200) {
        return jsonDecode(res.body) as Map<String, dynamic>;
      } else if (res.statusCode == 403) {
        throw Exception('Admin access required');
      } else if (res.statusCode == 404) {
        throw Exception('Answer not found');
      } else if (res.statusCode == 504) {
        throw Exception('Embedding timed out — please try again');
      } else {
        throw Exception('Failed to update verified answer');
      }
    } catch (e) {
      rethrow;
    }
  }

  Future<Map<String, dynamic>> createVerifiedAnswer({
    required String questionText,
    required String validatedAnswer,
    required String editorEmail,
    String? sourceManualId,
  }) async {
    try {
      final session = Supabase.instance.client.auth;
      final headers = <String, String>{'Content-Type': 'application/json'};
      final token = session.currentSession?.accessToken;
      if (token != null) headers['Authorization'] = 'Bearer $token';

      final res = await http.post(
        Uri.parse('${AppConfig.baseUrl}/manuals/verified-answers'),
        headers: headers,
        body: jsonEncode({
          'question_text': questionText,
          'validated_answer': validatedAnswer,
          'editor_email': editorEmail,
          if (sourceManualId != null) 'source_manual_id': sourceManualId,
        }),
      );

      if (res.statusCode == 200) {
        return jsonDecode(res.body) as Map<String, dynamic>;
      } else if (res.statusCode == 403) {
        throw Exception('Admin access required');
      } else if (res.statusCode == 422) {
        throw Exception('Question and answer are required');
      } else if (res.statusCode == 504) {
        throw Exception('Embedding timed out — please try again');
      } else {
        throw Exception('Failed to create verified answer');
      }
    } catch (e) {
      rethrow;
    }
  }

  Future<Map<String, dynamic>> deleteVerifiedAnswer({
    required String qaId,
    required String editorEmail,
  }) async {
    try {
      final session = Supabase.instance.client.auth;
      final headers = <String, String>{};
      final token = session.currentSession?.accessToken;
      if (token != null) headers['Authorization'] = 'Bearer $token';

      final res = await http.delete(
        Uri.parse(
            '${AppConfig.baseUrl}/manuals/verified-answers/$qaId?editor_email=${Uri.encodeComponent(editorEmail)}'),
        headers: headers,
      );

      if (res.statusCode == 200) {
        return jsonDecode(res.body) as Map<String, dynamic>;
      } else if (res.statusCode == 403) {
        throw Exception('Admin access required');
      } else if (res.statusCode == 404) {
        throw Exception('Answer not found');
      } else {
        throw Exception('Failed to delete verified answer');
      }
    } catch (e) {
      rethrow;
    }
  }

  Future<Map<String, dynamic>> generateQACandidates({
    required String manualId,
    int maxCandidates = 20,
    required String userEmail,
  }) async {
    try {
      final session = Supabase.instance.client.auth;
      final headers = <String, String>{'Content-Type': 'application/json'};
      final token = session.currentSession?.accessToken;
      if (token != null) headers['Authorization'] = 'Bearer $token';

      final res = await http.post(
        Uri.parse(
            '${AppConfig.baseUrl}/manuals/generate-qa-candidates?user_email=${Uri.encodeComponent(userEmail)}'),
        headers: headers,
        body: jsonEncode({
          'manual_id': manualId,
          'max_candidates': maxCandidates,
        }),
      );

      if (res.statusCode == 200) {
        return jsonDecode(res.body) as Map<String, dynamic>;
      } else if (res.statusCode == 403) {
        throw Exception('admin_required');
      } else if (res.statusCode == 404) {
        throw Exception('not_found');
      } else if (res.statusCode == 400) {
        final data = jsonDecode(res.body);
        final detail = data['detail'];
        final err = detail is Map ? (detail['message'] ?? detail['error']) : data['error'];
        throw Exception(err ?? 'no_chunks');
      } else {
        // Surface server error body so we can see what actually broke
        String detail = 'HTTP ${res.statusCode}';
        try {
          final body = jsonDecode(res.body);
          if (body is Map) {
            final d = body['detail'];
            detail = d is Map ? (d['message'] ?? d['error'] ?? d.toString()) : (d?.toString() ?? body.toString());
          } else {
            detail = body.toString();
          }
        } catch (_) {
          if (res.body.isNotEmpty) detail = res.body.substring(0, res.body.length.clamp(0, 300));
        }
        throw Exception('generation_failed: $detail');
      }
    } catch (e) {
      rethrow;
    }
  }

  Future<Map<String, dynamic>> saveTrainedEntry({
    required String question,
    required String answer,
    required String editorEmail,
    String? sourceManualId,
  }) async {
    // Step 1: create primary entry
    final result = await createVerifiedAnswer(
      questionText: question,
      validatedAnswer: answer,
      editorEmail: editorEmail,
      sourceManualId: sourceManualId,
    );
    final primaryQaId = result['id'] as String;

    // Steps 2-4: rollback primary on any failure
    try {
      final enVariants = await generateParaphraseVariants(
        questionText: question,
        userEmail: editorEmail,
        lang: 'en',
      );

      final arVariants = await generateParaphraseVariants(
        questionText: question,
        userEmail: editorEmail,
        lang: 'ar',
      );

      await reviewAnswerWithVariants(
        ratingId: '',
        action: 'retro_expand',
        userEmail: editorEmail,
        existingValidatedQaId: primaryQaId,
        variants: [...enVariants, ...arVariants],
      );

      return {
        'primaryQaId': primaryQaId,
        'englishCount': enVariants.length,
        'arabicCount': arVariants.length,
        'totalEmbeddings': enVariants.length + arVariants.length,
      };
    } catch (e) {
      // Rollback: remove the orphaned primary
      try {
        await deleteVerifiedAnswer(
          qaId: primaryQaId,
          editorEmail: editorEmail,
        );
      } catch (_) {
        // Best-effort cleanup; if delete fails, surface original error
      }
      rethrow;
    }
  }

  Future<List<Map<String, dynamic>>> getRealUsageSuggestions({
    required String userEmail,
  }) async {
    try {
      final session = Supabase.instance.client.auth;
      final headers = <String, String>{};
      final token = session.currentSession?.accessToken;
      if (token != null) headers['Authorization'] = 'Bearer $token';

      final res = await http.get(
        Uri.parse(
            '${AppConfig.baseUrl}/manuals/real-usage-suggestions?user_email=${Uri.encodeComponent(userEmail)}'),
        headers: headers,
      );

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        return (data['suggestions'] as List<dynamic>?)
                ?.map((e) => Map<String, dynamic>.from(e))
                .toList() ??
            [];
      } else if (res.statusCode == 403) {
        throw Exception('Admin access required');
      } else {
        throw Exception('Failed to fetch suggestions');
      }
    } catch (e) {
      rethrow;
    }
  }

  Future<Map<String, dynamic>> getStaleCacheEntries({
    required String userEmail,
  }) async {
    try {
      final session = Supabase.instance.client.auth;
      final headers = <String, String>{};
      final token = session.currentSession?.accessToken;
      if (token != null) headers['Authorization'] = 'Bearer $token';

      final res = await http.get(
        Uri.parse(
            '${AppConfig.baseUrl}/manuals/stale-cache-entries?user_email=${Uri.encodeComponent(userEmail)}'),
        headers: headers,
      );

      if (res.statusCode == 200) {
        return jsonDecode(res.body) as Map<String, dynamic>;
      } else if (res.statusCode == 403) {
        throw Exception('Admin access required');
      } else {
        throw Exception('Failed to fetch stale entries');
      }
    } catch (e) {
      rethrow;
    }
  }

  Future<Map<String, dynamic>> markCacheReviewed({
    required String qaId,
    required String action,
    required String userEmail,
    String? updatedQuestion,
    String? updatedAnswer,
  }) async {
    try {
      final session = Supabase.instance.client.auth;
      final headers = <String, String>{'Content-Type': 'application/json'};
      final token = session.currentSession?.accessToken;
      if (token != null) headers['Authorization'] = 'Bearer $token';

      final res = await http.post(
        Uri.parse(
            '${AppConfig.baseUrl}/manuals/mark-cache-reviewed?user_email=${Uri.encodeComponent(userEmail)}'),
        headers: headers,
        body: jsonEncode({
          'qa_id': qaId,
          'action': action,
          if (updatedQuestion != null) 'updated_question': updatedQuestion,
          if (updatedAnswer != null) 'updated_answer': updatedAnswer,
        }),
      );

      if (res.statusCode == 200) {
        return jsonDecode(res.body) as Map<String, dynamic>;
      } else if (res.statusCode == 403) {
        throw Exception('Admin access required');
      } else if (res.statusCode == 404) {
        throw Exception('not_found');
      } else if (res.statusCode == 400) {
        throw Exception('invalid_action');
      } else {
        throw Exception('review_failed');
      }
    } catch (e) {
      rethrow;
    }
  }
}
