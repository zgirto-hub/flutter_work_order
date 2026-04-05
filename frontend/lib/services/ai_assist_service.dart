import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config.dart';

class AiAssistService {
  Future<String> suggestDescription({
    required String title,
    String? location,
    String? type,
  }) async {
    final body = <String, dynamic>{
      'title': title,
    };
    if (location != null && location.isNotEmpty) {
      body['location'] = location;
    }
    if (type != null && type.isNotEmpty) {
      body['type'] = type;
    }

    try {
      final res = await http
          .post(
            Uri.parse('${AppConfig.baseUrl}/ai/suggest'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 65));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        return data['description'] as String;
      } else if (res.statusCode == 503) {
        throw Exception(
            'AI service is currently unavailable. Please try again later.');
      } else if (res.statusCode == 502) {
        throw Exception(
            'AI could not generate a description. Please try again.');
      } else {
        throw Exception('Failed to get AI suggestion.');
      }
    } catch (e) {
      if (e.toString().contains('TimeoutException')) {
        throw Exception('Request timed out. Please try again.');
      }
      throw Exception('Failed to get AI suggestion.');
    }
  }
}
