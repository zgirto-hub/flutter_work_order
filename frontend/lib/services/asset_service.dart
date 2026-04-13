import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config.dart';
import '../models/asset.dart';

class AssetService {
  Map<String, String> _headers() {
    final session = Supabase.instance.client.auth;
    final token = session.currentSession?.accessToken;
    final headers = <String, String>{
      'Content-Type': 'application/json',
    };
    if (token != null) {
      headers['Authorization'] = 'Bearer $token';
    }
    return headers;
  }

  Future<List<Asset>> fetchAssets() async {
    final userEmail = Supabase.instance.client.auth.currentUser?.email ?? '';
    final res = await http.get(
      Uri.parse(
          '${AppConfig.baseUrl}/asset-registry/assets?user_email=${Uri.encodeComponent(userEmail)}'),
      headers: _headers(),
    );

    if (res.statusCode == 200) {
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final assets = data['assets'] as List<dynamic>? ?? [];
      return assets.map((e) => Asset.fromJson(e)).toList();
    } else if (res.statusCode == 403) {
      throw Exception('Admin access required');
    } else {
      throw Exception('Failed to load assets');
    }
  }

  Future<Asset> createAsset({
    required String name,
    required String type,
    required String location,
    String notes = '',
  }) async {
    final userEmail = Supabase.instance.client.auth.currentUser?.email ?? '';
    final res = await http.post(
      Uri.parse(
          '${AppConfig.baseUrl}/asset-registry/assets?user_email=${Uri.encodeComponent(userEmail)}'),
      headers: _headers(),
      body: jsonEncode({
        'name': name,
        'type': type,
        'location': location,
        'notes': notes,
      }),
    );

    if (res.statusCode == 200) {
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      return Asset.fromJson(data['asset']);
    } else if (res.statusCode == 403) {
      throw Exception('Admin access required');
    } else if (res.statusCode == 409) {
      final err = jsonDecode(res.body);
      throw Exception(err['detail'] ?? 'Asset already exists');
    } else if (res.statusCode == 400) {
      final err = jsonDecode(res.body);
      throw Exception(err['detail'] ?? 'Invalid request');
    } else {
      throw Exception('Failed to create asset');
    }
  }

  Future<Asset> updateAsset(
    String assetId, {
    String? name,
    String? type,
    String? location,
    String? notes,
  }) async {
    final userEmail = Supabase.instance.client.auth.currentUser?.email ?? '';
    final body = <String, dynamic>{};
    if (name != null) body['name'] = name;
    if (type != null) body['type'] = type;
    if (location != null) body['location'] = location;
    if (notes != null) body['notes'] = notes;

    final res = await http.put(
      Uri.parse(
          '${AppConfig.baseUrl}/asset-registry/assets/$assetId?user_email=${Uri.encodeComponent(userEmail)}'),
      headers: _headers(),
      body: jsonEncode(body),
    );

    if (res.statusCode == 200) {
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      return Asset.fromJson(data['asset']);
    } else if (res.statusCode == 403) {
      throw Exception('Admin access required');
    } else if (res.statusCode == 404) {
      throw Exception('Asset not found');
    } else if (res.statusCode == 409) {
      final err = jsonDecode(res.body);
      throw Exception(err['detail'] ?? 'Asset already exists');
    } else if (res.statusCode == 400) {
      final err = jsonDecode(res.body);
      throw Exception(err['detail'] ?? 'Invalid request');
    } else {
      throw Exception('Failed to update asset');
    }
  }

  Future<void> deleteAsset(String assetId) async {
    final userEmail = Supabase.instance.client.auth.currentUser?.email ?? '';
    final res = await http.delete(
      Uri.parse(
          '${AppConfig.baseUrl}/asset-registry/assets/$assetId?user_email=${Uri.encodeComponent(userEmail)}'),
      headers: _headers(),
    );

    if (res.statusCode == 200) {
      return;
    } else if (res.statusCode == 403) {
      throw Exception('Admin access required');
    } else if (res.statusCode == 404) {
      throw Exception('Asset not found');
    } else {
      throw Exception('Failed to delete asset');
    }
  }

  Future<AssetSystemLink> addLink(
    String assetId, {
    required String system,
    required String role,
  }) async {
    final userEmail = Supabase.instance.client.auth.currentUser?.email ?? '';
    final res = await http.post(
      Uri.parse(
          '${AppConfig.baseUrl}/asset-registry/assets/$assetId/links?user_email=${Uri.encodeComponent(userEmail)}'),
      headers: _headers(),
      body: jsonEncode({
        'system': system,
        'role': role,
      }),
    );

    if (res.statusCode == 200) {
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      return AssetSystemLink.fromJson(data['link']);
    } else if (res.statusCode == 403) {
      throw Exception('Admin access required');
    } else if (res.statusCode == 404) {
      throw Exception('Asset not found');
    } else if (res.statusCode == 409) {
      final err = jsonDecode(res.body);
      throw Exception(err['detail'] ?? 'Link already exists');
    } else if (res.statusCode == 400) {
      final err = jsonDecode(res.body);
      throw Exception(err['detail'] ?? 'Invalid request');
    } else {
      throw Exception('Failed to add link');
    }
  }

  Future<void> removeLink(String linkId) async {
    final userEmail = Supabase.instance.client.auth.currentUser?.email ?? '';
    final res = await http.delete(
      Uri.parse(
          '${AppConfig.baseUrl}/asset-registry/links/$linkId?user_email=${Uri.encodeComponent(userEmail)}'),
      headers: _headers(),
    );

    if (res.statusCode == 200) {
      return;
    } else if (res.statusCode == 403) {
      throw Exception('Admin access required');
    } else if (res.statusCode == 404) {
      throw Exception('Link not found');
    } else {
      throw Exception('Failed to remove link');
    }
  }
}
