import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/work_order.dart';

class WorkOrderService {
  final _client = Supabase.instance.client;

  // ✅ FETCH (Map → WorkOrder model)
  Future<List<WorkOrder>> fetchWorkOrders() async {
    final response = await _client
        .from('work_orders')
        .select()
        .order('created_at', ascending: false);

    return response.map<WorkOrder>((json) => WorkOrder.fromJson(json)).toList();
  }

  // ✅ INSERT
  Future<void> addWorkOrder(WorkOrder workOrder) async {
    await _client.from('work_orders').insert({
      'job_no': workOrder.jobNo, // 🔥 THIS WAS MISSING
      'title': workOrder.client,
      'description': workOrder.description,
      'status': workOrder.status,
      'location': workOrder.location,
      'type': workOrder.type,
      'created_by': _client.auth.currentUser?.id,
    });
  }

  // ✅ UPDATE
  Future<void> updateWorkOrder(WorkOrder workOrder) async {
    await _client
        .from('work_orders')
        .update(workOrder.toJson())
        .eq('id', workOrder.jobNo);
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
