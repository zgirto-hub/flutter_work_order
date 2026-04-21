import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/ai_provider.dart';
import '../config.dart';

class AiProviderService {
  Future<AiProvidersResponse> listProviders() async {
    final userEmail = Supabase.instance.client.auth.currentUser?.email;
    if (userEmail == null) {
      throw Exception('Not authenticated');
    }

    final res = await http.get(
      Uri.parse(
          '${AppConfig.baseUrl}/ai/providers?user_email=${Uri.encodeComponent(userEmail)}'),
    );
    if (res.statusCode != 200) {
      throw Exception('Failed to fetch providers');
    }
    final data = jsonDecode(res.body);
    return AiProvidersResponse.fromJson(data);
  }

  Future<void> setActiveProvider(String key, String userEmail) async {
    final res = await http.post(
      Uri.parse(
          '${AppConfig.baseUrl}/ai/provider?admin_email=${Uri.encodeComponent(userEmail)}'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'provider': key}),
    );
    if (res.statusCode != 200) {
      final data = jsonDecode(res.body);
      throw Exception(data['detail'] ?? 'Failed to set provider');
    }
  }

  Future<({String provider, bool healthy, String? reason})> getHealth(
      String userEmail) async {
    final res = await http.get(
      Uri.parse(
          '${AppConfig.baseUrl}/ai/provider/health?admin_email=${Uri.encodeComponent(userEmail)}'),
    );
    if (res.statusCode != 200) {
      throw Exception('Failed to check health');
    }
    final data = jsonDecode(res.body);
    return (
      provider: data['provider'] as String,
      healthy: data['healthy'] as bool,
      reason: data['reason'] as String?,
    );
  }

  Future<bool> getSmartPreprocessing(String userEmail) async {
    final res = await http.get(
      Uri.parse(
          '${AppConfig.baseUrl}/settings/smart-preprocessing?admin_email=${Uri.encodeComponent(userEmail)}'),
    );
    if (res.statusCode != 200) {
      throw Exception('Failed to fetch smart preprocessing status');
    }
    final data = jsonDecode(res.body);
    return data['enabled'] as bool;
  }

  Future<({List<Map<String, String>> models, String activeModel})>
      getGeminiModels(String userEmail) async {
    final res = await http.get(
      Uri.parse(
          '${AppConfig.baseUrl}/ai/gemini/models?admin_email=${Uri.encodeComponent(userEmail)}'),
    );
    if (res.statusCode != 200) {
      throw Exception('Failed to fetch Gemini models');
    }
    final data = jsonDecode(res.body);
    final models = (data['models'] as List)
        .map((m) => {
              'id': m['id'] as String,
              'name': m['name'] as String,
              'free_quota': m['free_quota'] as String,
            })
        .toList();
    return (models: models, activeModel: data['active_model'] as String);
  }

  Future<void> setGeminiModel(String model, String userEmail) async {
    final res = await http.post(
      Uri.parse(
          '${AppConfig.baseUrl}/ai/gemini/model?admin_email=${Uri.encodeComponent(userEmail)}'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'model': model}),
    );
    if (res.statusCode != 200) {
      final data = jsonDecode(res.body);
      throw Exception(data['detail'] ?? 'Failed to set Gemini model');
    }
  }

  Future<void> setSmartPreprocessing(bool enabled, String userEmail) async {
    final res = await http.put(
      Uri.parse(
          '${AppConfig.baseUrl}/settings/smart-preprocessing?admin_email=${Uri.encodeComponent(userEmail)}'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'enabled': enabled}),
    );
    if (res.statusCode != 200) {
      final data = jsonDecode(res.body);
      throw Exception(data['detail'] ?? 'Failed to set smart preprocessing');
    }
  }

  Future<bool> getAiWorkOrderEnabled(String userEmail) async {
    try {
      final res = await http.get(
        Uri.parse(
            '${AppConfig.baseUrl}/settings/ai-work-order?admin_email=${Uri.encodeComponent(userEmail)}'),
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        return data['enabled'] as bool;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> getAiWorkOrderEnabledForUser() async {
    try {
      final res = await http.get(
        Uri.parse('${AppConfig.baseUrl}/ai/autofill-work-order/status'),
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        return data['enabled'] as bool;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  Future<void> setAiWorkOrderEnabled(bool enabled, String userEmail) async {
    final res = await http.put(
      Uri.parse(
          '${AppConfig.baseUrl}/settings/ai-work-order?admin_email=${Uri.encodeComponent(userEmail)}'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'enabled': enabled}),
    );
    if (res.statusCode != 200) {
      final data = jsonDecode(res.body);
      throw Exception(data['detail'] ?? 'Failed to set AI Work Order setting');
    }
  }
}
