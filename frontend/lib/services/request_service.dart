import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/request_model.dart';

class RequestService {
  final _client = Supabase.instance.client;

  Future<String> getUserRole(String email) async {
    final res = await _client
        .from('user_profiles')
        .select('user_type')
        .eq('email', email)
        .maybeSingle();
    return res?['user_type'] as String? ?? 'admin';
  }

  Future<List<RequestModel>> fetchRequests({
    required String email,
    required String userRole,
  }) async {
    var query = _client.from('requests').select('*');
    if (userRole == 'requester') {
      query = query.eq('created_by', email);
    }
    final res = await query.order('created_at', ascending: false);
    return res.map<RequestModel>((j) => RequestModel.fromJson(j)).toList();
  }

  Future<void> createRequest({
    required String title,
    required String description,
    required String createdBy,
    required String requesterName,
    required String location,
  }) async {
    await _client.from('requests').insert({
      'title': title,
      'description': description,
      'created_by': createdBy,
      'requester_name': requesterName,
      'location': location,
      'status': 'Open',
    });
  }

  Future<void> closeRequest({
    required String id,
    required String closedBy,
    String? techNotes,
  }) async {
    await _client.from('requests').update({
      'status': 'Closed',
      'closed_by': closedBy,
      'closed_at': DateTime.now().toIso8601String(),
      'tech_notes': techNotes,
    }).eq('id', id);
  }
}
