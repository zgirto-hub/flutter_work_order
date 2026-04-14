import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config.dart';
import '../models/asset.dart';

class AssetServiceException implements Exception {
  final String message;
  final String? code;
  final String? conflictWithLinkId;

  AssetServiceException(this.message, {this.code, this.conflictWithLinkId});

  @override
  String toString() => message;
}

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

    if (res.statusCode == 200 || res.statusCode == 201) {
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

  Future<List<String>> fetchAssetNames() async {
    try {
      final res = await http.get(
        Uri.parse('${AppConfig.baseUrl}/asset-registry/asset-names'),
        headers: _headers(),
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final names = data['names'] as List<dynamic>? ?? [];
        return names.map((e) => e.toString()).toList();
      }
      return [];
    } catch (_) {
      return [];
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
    String? system,
    String? systemId,
    required String role,
    required String site,
  }) async {
    final userEmail = Supabase.instance.client.auth.currentUser?.email ?? '';
    final res = await http.post(
      Uri.parse(
          '${AppConfig.baseUrl}/asset-registry/assets/$assetId/links?user_email=${Uri.encodeComponent(userEmail)}'),
      headers: _headers(),
      body: jsonEncode({
        if (system != null) 'system': system,
        if (systemId != null) 'system_id': systemId,
        'role': role,
        'site': site,
      }),
    );

    if (res.statusCode == 200 || res.statusCode == 201) {
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      return AssetSystemLink.fromJson(data['link']);
    } else if (res.statusCode == 403) {
      throw Exception('Admin access required');
    } else if (res.statusCode == 404) {
      throw Exception('Asset not found');
    } else if (res.statusCode == 409) {
      throw _parseAssetError(res, fallback: 'Link already exists');
    } else if (res.statusCode == 400) {
      throw _parseAssetError(res, fallback: 'Invalid request');
    } else {
      throw Exception('Failed to add link');
    }
  }

  Future<AssetSystemLink> updateLink(
    String linkId, {
    String? role,
    String? site,
  }) async {
    final userEmail = Supabase.instance.client.auth.currentUser?.email ?? '';
    final res = await http.patch(
      Uri.parse(
          '${AppConfig.baseUrl}/asset-registry/links/$linkId?user_email=${Uri.encodeComponent(userEmail)}'),
      headers: _headers(),
      body: jsonEncode({
        if (role != null) 'role': role,
        if (site != null) 'site': site,
      }),
    );

    if (res.statusCode == 200) {
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      return AssetSystemLink.fromJson(data['link']);
    } else if (res.statusCode == 403) {
      throw AssetServiceException('Admin access required');
    } else if (res.statusCode == 404) {
      throw AssetServiceException('Link not found');
    } else if (res.statusCode == 409 || res.statusCode == 400) {
      throw _parseAssetError(res, fallback: 'Failed to update link');
    } else {
      throw AssetServiceException('Failed to update link');
    }
  }

  Future<void> deleteLink(String linkId) async {
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

  Future<void> removeLink(String linkId) => deleteLink(linkId);

  Future<List<Map<String, dynamic>>> fetchSuggestions() async {
    try {
      final userEmail = Supabase.instance.client.auth.currentUser?.email ?? '';
      final res = await http.get(
        Uri.parse(
            '${AppConfig.baseUrl}/asset-registry/suggestions?user_email=${Uri.encodeComponent(userEmail)}'),
        headers: _headers(),
      );

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final suggestions = data['suggestions'] as List<dynamic>? ?? [];
        return suggestions.map((e) => Map<String, dynamic>.from(e)).toList();
      } else if (res.statusCode == 403) {
        return [];
      }
      return [];
    } catch (_) {
      return [];
    }
  }

  Future<void> dismissSuggestion(String equipmentId) async {
    final userEmail = Supabase.instance.client.auth.currentUser?.email ?? '';
    final res = await http.post(
      Uri.parse(
          '${AppConfig.baseUrl}/asset-registry/suggestions/dismiss?user_email=${Uri.encodeComponent(userEmail)}'),
      headers: _headers(),
      body: jsonEncode({'equipment_id': equipmentId}),
    );

    if (res.statusCode == 200) {
      return;
    } else if (res.statusCode == 403) {
      throw Exception('Admin access required');
    } else if (res.statusCode == 400) {
      final err = jsonDecode(res.body);
      throw Exception(err['detail'] ?? 'Invalid request');
    } else {
      throw Exception('Failed to dismiss suggestion');
    }
  }

  AssetServiceException _parseAssetError(http.Response res,
      {required String fallback}) {
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final detail = data['detail'];
    if (detail is Map<String, dynamic>) {
      return AssetServiceException(
        detail['detail'] as String? ?? (detail['error'] as String? ?? fallback),
        code: detail['error'] as String?,
        conflictWithLinkId: detail['conflict_with_link_id'] as String?,
      );
    }
    if (detail is String) {
      return AssetServiceException(detail);
    }
    return AssetServiceException(fallback);
  }
}
