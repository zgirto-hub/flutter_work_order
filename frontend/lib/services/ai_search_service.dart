import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/nl_search_result.dart';

class AiSearchService {
  final String baseUrl;
  final String email;

  AiSearchService({required this.baseUrl, required this.email});

  Future<NLSearchResult> searchWorkOrders(
    String query,
    String userRole, {
    int limit = 30,
    int offset = 0,
  }) async {
    final body = <String, dynamic>{
      'query': query,
      'email': email,
      'user_role': userRole,
      'limit': limit,
      'offset': offset,
    };

    try {
      final res = await http
          .post(
            Uri.parse('$baseUrl/search/nl'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 15));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        return NLSearchResult.fromJson(data as Map<String, dynamic>);
      } else if (res.statusCode == 422) {
        final data = jsonDecode(res.body);
        throw Exception(data['detail'] ?? 'Validation error');
      } else {
        throw Exception('Search request failed');
      }
    } on TimeoutException {
      throw Exception('Search request timed out');
    }
  }

  Future<NLSearchResult> searchWithFilters(
    Map<String, dynamic> filters,
    String userRole, {
    int limit = 30,
    int offset = 0,
  }) async {
    final body = <String, dynamic>{
      'filters': filters,
      'email': email,
      'user_role': userRole,
      'limit': limit,
      'offset': offset,
    };

    try {
      final res = await http
          .post(
            Uri.parse('$baseUrl/search/nl'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 15));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        return NLSearchResult.fromJson(data as Map<String, dynamic>);
      } else if (res.statusCode == 422) {
        final data = jsonDecode(res.body);
        throw Exception(data['detail'] ?? 'Validation error');
      } else {
        throw Exception('Search request failed');
      }
    } on TimeoutException {
      throw Exception('Search request timed out');
    }
  }
}
