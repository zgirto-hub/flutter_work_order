import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/work_order.dart';

class WorkOrderService {
  final SupabaseClient _client = Supabase.instance.client;

  // ✅ FETCH ALL WORK ORDERS
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

  // ✅ ADD WORK ORDER (returns full inserted object)
  Future<WorkOrder> addWorkOrder(WorkOrder workOrder) async {
  final user = _client.auth.currentUser;

  if (user == null) {
    throw Exception("User not authenticated");
  }

  // 1️⃣ Insert Work Order
  final workOrderResponse = await _client
      .from('work_orders')
      .insert({
        'title': workOrder.Title,
        'description': workOrder.description,
        'status': workOrder.status,
        'location': workOrder.location,
        'type': workOrder.type,
        'created_by': user.id,
      })
      .select()
      .single();

  final workOrderId = workOrderResponse['id'];

  // 2️⃣ Insert Employee Assignments
  if (workOrder.assignedEmployees.isNotEmpty) {
    final assignments = workOrder.assignedEmployees
        .map((emp) => {
              'work_order_id': workOrderId,
              'employee_id': emp.id,
            })
        .toList();

    await _client.from('work_order_assignments').insert(assignments);
  }

  // 3️⃣ Fetch full object with employees
  final fullResponse = await _client
      .from('work_orders')
      .select('''
        *,
        work_order_assignments (
          employee_id,
          employees (
            id,
            full_name
          )
        )
      ''')
      .eq('id', workOrderId)
      .single();

  return WorkOrder.fromJson(fullResponse);
}

  // ✅ UPDATE WORK ORDER
  Future<void> updateWorkOrder(WorkOrder workOrder) async {
  // 1️⃣ Update main work order
  await _client
      .from('work_orders')
      .update(workOrder.toJson())
      .eq('id', workOrder.id);

  // 2️⃣ Remove existing assignments
  await _client
      .from('work_order_assignments')
      .delete()
      .eq('work_order_id', workOrder.id);

  // 3️⃣ Insert new assignments
  if (workOrder.assignedEmployees.isNotEmpty) {
    final assignments = workOrder.assignedEmployees.map((emp) {
      return {
        'work_order_id': workOrder.id,
        'employee_id': emp.id,
      };
    }).toList();

    await _client.from('work_order_assignments').insert(assignments);
  }
}

  // ✅ DELETE WORK ORDER
  Future<void> deleteWorkOrder(String id) async {
    await _client.from('work_orders').delete().eq('id', id);
  }

  // ✅ REAL-TIME STREAM (optional usage)
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
