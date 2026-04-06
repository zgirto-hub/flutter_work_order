import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config.dart';

class AiInsightsService {
  Future<Map<String, dynamic>> getInsight({
    required String insightType,
    required String email,
    required String userRole,
    int dateRangeDays = 30,
    String language = "en",
  }) async {
    final body = <String, dynamic>{
      'insight_type': insightType,
      'date_range_days': dateRangeDays,
      'language': language,
    };

    try {
      final res = await http
          .post(
            Uri.parse(
                '${AppConfig.baseUrl}/ai/insights?email=$email&user_role=$userRole'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 65));

      if (res.statusCode == 200) {
        return jsonDecode(res.body) as Map<String, dynamic>;
      } else if (res.statusCode == 403) {
        throw Exception(
            'Access denied. Admin or supervisor role required.');
      } else if (res.statusCode == 503) {
        throw Exception(
            'AI service is currently unavailable. Please try again later.');
      } else if (res.statusCode == 502) {
        throw Exception(
            'AI could not generate insights. Please try again.');
      } else if (res.statusCode == 422) {
        final data = jsonDecode(res.body);
        throw Exception(data['detail'] as String);
      } else {
        throw Exception('Failed to get AI insights.');
      }
    } on TimeoutException {
      throw Exception('Request timed out. Please try again.');
    }
  }
}
