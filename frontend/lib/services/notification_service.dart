import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config.dart';
import '../models/app_notification.dart';

class NotificationService {
  String get _email =>
      Supabase.instance.client.auth.currentUser?.email?.trim().toLowerCase() ?? '';

  Future<int> unreadCount() async {
    if (_email.isEmpty) return 0;
    final res = await http.get(
      Uri.parse(
        '${AppConfig.baseUrl}/notifications/unread-count?email=${Uri.encodeComponent(_email)}',
      ),
    );
    if (res.statusCode != 200) return 0;
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    return (data['count'] as num?)?.toInt() ?? 0;
  }

  Future<List<AppNotification>> fetchNotifications({
    bool unreadOnly = false,
    int limit = 50,
    int offset = 0,
  }) async {
    if (_email.isEmpty) return [];
    final uri = Uri.parse('${AppConfig.baseUrl}/notifications').replace(
      queryParameters: {
        'email': _email,
        'unread_only': unreadOnly.toString(),
        'limit': limit.toString(),
        'offset': offset.toString(),
      },
    );
    final res = await http.get(uri);
    if (res.statusCode != 200) return [];
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final list = data['notifications'] as List<dynamic>? ?? const [];
    return list
        .map((e) => AppNotification.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> markRead(String notificationId) async {
    if (_email.isEmpty) return;
    await http.patch(
      Uri.parse(
        '${AppConfig.baseUrl}/notifications/$notificationId/read?email=${Uri.encodeComponent(_email)}',
      ),
    );
  }

  Future<void> markAllRead() async {
    if (_email.isEmpty) return;
    await http.patch(
      Uri.parse(
        '${AppConfig.baseUrl}/notifications/read-all?email=${Uri.encodeComponent(_email)}',
      ),
    );
  }
}
