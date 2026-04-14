import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config.dart';
import '../models/system.dart';

class SystemsServiceException implements Exception {
  final String message;
  final String? code;
  final int? count;

  SystemsServiceException(this.message, {this.code, this.count});

  @override
  String toString() => message;
}

class SystemDetailLink {
  final String linkId;
  final String id;
  final String name;
  final String type;
  final String location;

  const SystemDetailLink({
    required this.linkId,
    required this.id,
    required this.name,
    required this.type,
    required this.location,
  });

  factory SystemDetailLink.fromJson(Map<String, dynamic> json) {
    final asset = Map<String, dynamic>.from(json['asset'] as Map);
    return SystemDetailLink(
      linkId: json['link_id'] as String,
      id: asset['id'] as String,
      name: asset['name'] as String,
      type: asset['type'] as String,
      location: asset['location'] as String,
    );
  }
}

class SystemDetailSite {
  final List<SystemDetailLink> primary;
  final List<SystemDetailLink> standby;
  final List<SystemDetailLink> client;

  const SystemDetailSite({
    required this.primary,
    required this.standby,
    required this.client,
  });

  int get assetCount => primary.length + standby.length + client.length;

  factory SystemDetailSite.fromJson(Map<String, dynamic> json) {
    List<SystemDetailLink> parseList(String key) {
      final value = json[key] as List<dynamic>? ?? const [];
      return value
          .map((entry) => SystemDetailLink.fromJson(
              Map<String, dynamic>.from(entry as Map)))
          .toList();
    }

    return SystemDetailSite(
      primary: parseList('primary'),
      standby: parseList('standby'),
      client: parseList('client'),
    );
  }
}

class SystemDetail {
  final System system;
  final SystemDetailSite production;
  final SystemDetailSite? contingency;

  const SystemDetail({
    required this.system,
    required this.production,
    required this.contingency,
  });

  int get assetCount => production.assetCount + (contingency?.assetCount ?? 0);

  factory SystemDetail.fromJson(Map<String, dynamic> json) {
    return SystemDetail(
      system: System.fromJson(Map<String, dynamic>.from(json['system'] as Map)),
      production: SystemDetailSite.fromJson(
        Map<String, dynamic>.from(json['production'] as Map),
      ),
      contingency: json['contingency'] == null
          ? null
          : SystemDetailSite.fromJson(
              Map<String, dynamic>.from(json['contingency'] as Map),
            ),
    );
  }
}

class SystemsService {
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

  Future<List<System>> fetchSystems({
    bool activeOnly = true,
    bool needsReview = false,
  }) async {
    final userEmail = Supabase.instance.client.auth.currentUser?.email ?? '';
    final queryParams = [
      'user_email=${Uri.encodeComponent(userEmail)}',
      'active_only=$activeOnly',
      'needs_review=$needsReview',
    ].join('&');
    final res = await http.get(
      Uri.parse('${AppConfig.baseUrl}/systems?$queryParams'),
      headers: _headers(),
    );

    if (res.statusCode == 200) {
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final systems = data['systems'] as List<dynamic>? ?? [];
      return systems.map((e) => System.fromJson(e)).toList();
    } else {
      throw Exception('Failed to load systems');
    }
  }

  Future<System> createSystem({
    required String name,
    String? category,
    int? sortOrder,
    bool hasContingency = false,
  }) async {
    final userEmail = Supabase.instance.client.auth.currentUser?.email ?? '';
    final res = await http.post(
      Uri.parse(
          '${AppConfig.baseUrl}/systems?user_email=${Uri.encodeComponent(userEmail)}'),
      headers: _headers(),
      body: jsonEncode({
        'name': name,
        if (category != null) 'category': category,
        if (sortOrder != null) 'sort_order': sortOrder,
        'has_contingency': hasContingency,
      }),
    );

    if (res.statusCode == 201) {
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      return System.fromJson(data);
    } else if (res.statusCode == 403) {
      throw Exception('Admin access required');
    } else if (res.statusCode == 409) {
      throw Exception('System name already exists');
    } else {
      throw Exception('Failed to create system');
    }
  }

  Future<System> updateSystem(
    String id, {
    String? name,
    String? category,
    int? sortOrder,
    bool? hasContingency,
  }) async {
    final userEmail = Supabase.instance.client.auth.currentUser?.email ?? '';
    final res = await http.patch(
      Uri.parse(
          '${AppConfig.baseUrl}/systems/$id?user_email=${Uri.encodeComponent(userEmail)}'),
      headers: _headers(),
      body: jsonEncode({
        if (name != null) 'name': name,
        if (category != null) 'category': category,
        if (sortOrder != null) 'sort_order': sortOrder,
        if (hasContingency != null) 'has_contingency': hasContingency,
      }),
    );

    if (res.statusCode == 200) {
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      return System.fromJson(data);
    } else if (res.statusCode == 403) {
      throw Exception('Admin access required');
    } else if (res.statusCode == 404) {
      throw Exception('System not found');
    } else if (res.statusCode == 409) {
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final detail = data['detail'];
      if (detail is Map<String, dynamic> &&
          detail['error'] == 'contingency_assets_exist') {
        throw SystemsServiceException(
          'Contingency assets still exist',
          code: 'contingency_assets_exist',
          count: detail['count'] as int?,
        );
      }
      throw SystemsServiceException('System name already exists');
    } else {
      throw Exception('Failed to update system');
    }
  }

  Future<SystemDetail> fetchSystemDetail(String id) async {
    final userEmail = Supabase.instance.client.auth.currentUser?.email ?? '';
    final res = await http.get(
      Uri.parse(
        '${AppConfig.baseUrl}/systems/$id/detail?user_email=${Uri.encodeComponent(userEmail)}',
      ),
      headers: _headers(),
    );

    if (res.statusCode == 200) {
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      return SystemDetail.fromJson(data);
    } else if (res.statusCode == 403) {
      throw SystemsServiceException('Admin access required');
    } else if (res.statusCode == 404) {
      throw SystemsServiceException('System not found');
    } else {
      throw SystemsServiceException('Failed to load system detail');
    }
  }

  Future<Map<String, dynamic>> disableContingency(String id) async {
    final userEmail = Supabase.instance.client.auth.currentUser?.email ?? '';
    final res = await http.post(
      Uri.parse(
        '${AppConfig.baseUrl}/systems/$id/disable-contingency?user_email=${Uri.encodeComponent(userEmail)}',
      ),
      headers: _headers(),
    );

    if (res.statusCode == 200) {
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      return {
        'system':
            System.fromJson(Map<String, dynamic>.from(data['system'] as Map)),
        'moved': data['moved'] as int? ?? 0,
        'demoted': data['demoted'] as int? ?? 0,
      };
    } else if (res.statusCode == 403) {
      throw SystemsServiceException('Admin access required');
    } else if (res.statusCode == 404) {
      throw SystemsServiceException('System not found');
    } else {
      throw SystemsServiceException('Failed to disable contingency');
    }
  }

  Future<Map<String, dynamic>> retireSystem(String id) async {
    final userEmail = Supabase.instance.client.auth.currentUser?.email ?? '';
    final res = await http.patch(
      Uri.parse(
          '${AppConfig.baseUrl}/systems/$id/retire?user_email=${Uri.encodeComponent(userEmail)}'),
      headers: _headers(),
    );

    if (res.statusCode == 200) {
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      return {
        'system': System.fromJson(data['system']),
        if (data.containsKey('warning')) 'warning': data['warning'],
      };
    } else if (res.statusCode == 403) {
      throw Exception('Admin access required');
    } else if (res.statusCode == 404) {
      throw Exception('System not found');
    } else {
      throw Exception('Failed to retire system');
    }
  }

  Future<System> activateSystem(String id) async {
    final userEmail = Supabase.instance.client.auth.currentUser?.email ?? '';
    final res = await http.patch(
      Uri.parse(
          '${AppConfig.baseUrl}/systems/$id/activate?user_email=${Uri.encodeComponent(userEmail)}'),
      headers: _headers(),
    );

    if (res.statusCode == 200) {
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      return System.fromJson(data);
    } else if (res.statusCode == 403) {
      throw Exception('Admin access required');
    } else if (res.statusCode == 404) {
      throw Exception('System not found');
    } else {
      throw Exception('Failed to activate system');
    }
  }
}
