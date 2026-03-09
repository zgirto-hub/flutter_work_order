import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/employee.dart';

class EmployeeService {
  final _client = Supabase.instance.client;

  Future<List<Employee>> fetchEmployees() async {
    final response = await _client
        .from('employees')
        .select()
        .eq('active', true)
        .order('full_name');

    return response.map<Employee>((json) => Employee.fromJson(json)).toList();
  }
}
