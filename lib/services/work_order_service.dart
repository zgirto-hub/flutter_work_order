import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/work_order.dart';

class WorkOrderService {
  final _client = Supabase.instance.client;

  Future<List<WorkOrder>> fetchWorkOrders() async {
    final response = await _client.from('work_orders').select('''
        *,
        work_order_assignments (
          employee_id,
          employees (
            id,
            full_name
          )
        )
      ''').order('created_at', ascending: false);

    return response.map<WorkOrder>((json) => WorkOrder.fromJson(json)).toList();
  }

  Future<String> addWorkOrder(WorkOrder workOrder) async {
    final user = _client.auth.currentUser;

    if (user == null) {
      throw Exception("User not authenticated");
    }

    final response = await _client
        .from('work_orders')
        .insert({
          'job_no': workOrder.jobNo,
          'title': workOrder.Title,
          'description': workOrder.description,
          'status': workOrder.status,
          'location': workOrder.location,
          'type': workOrder.type,
          'created_by': user.id,
        })
        .select()
        .single();

    return response['id']; // 🔥 return inserted ID
  }

  // ✅ UPDATE
  Future<void> updateWorkOrder(WorkOrder workOrder) async {
    await _client
        .from('work_orders')
        .update(workOrder.toJson())
        .eq('id', workOrder.id);
  }

  // ✅ DELETE
  Future<void> deleteWorkOrder(String id) async {
    await _client.from('work_orders').delete().eq('id', id);
  }

  Stream<List<WorkOrder>> streamWorkOrders() {
    return _client
        .from('work_orders')
        .stream(primaryKey: ['id'])
        .order('created_at', ascending: false)
        .map(
          (data) =>
              data.map<WorkOrder>((json) => WorkOrder.fromJson(json)).toList(),
        );
  }
}
