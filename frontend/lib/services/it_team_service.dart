import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config.dart';

class ItTeamService {
  Future<List<Map<String, dynamic>>> getItTeams() async {
    try {
      final res = await http.get(
        Uri.parse('${AppConfig.baseUrl}/it-teams'),
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        return (data['it_teams'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      }
    } catch (_) {}
    return [];
  }

  Future<Map<String, dynamic>?> createItTeam(String name) async {
    try {
      final res = await http.post(
        Uri.parse('${AppConfig.baseUrl}/it-teams'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'name': name}),
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        return data['it_team'];
      } else {
        final error = jsonDecode(res.body);
        throw Exception(error['detail'] ?? 'Failed to create IT team');
      }
    } catch (e) {
      rethrow;
    }
  }

  Future<Map<String, dynamic>?> updateItTeam(String id, String name) async {
    try {
      final res = await http.patch(
        Uri.parse('${AppConfig.baseUrl}/it-teams/$id'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'name': name}),
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        return data['it_team'];
      } else {
        final error = jsonDecode(res.body);
        throw Exception(error['detail'] ?? 'Failed to update IT team');
      }
    } catch (e) {
      rethrow;
    }
  }

  Future<void> deleteItTeam(String id) async {
    try {
      final res = await http.delete(
        Uri.parse('${AppConfig.baseUrl}/it-teams/$id'),
      );
      if (res.statusCode != 200) {
        final error = jsonDecode(res.body);
        throw Exception(error['detail'] ?? 'Failed to delete IT team');
      }
    } catch (e) {
      rethrow;
    }
  }
}
