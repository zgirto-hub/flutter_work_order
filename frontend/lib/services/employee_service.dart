import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/employee.dart';
import '../config.dart';

class EmployeeService {
  Future<List<Employee>> fetchEmployees() async {
    final res = await http.get(
      Uri.parse('${AppConfig.baseUrl}/employees'),
    );
    if (res.statusCode != 200) {
      throw Exception('Failed to fetch employees');
    }
    final data = jsonDecode(res.body);
    final list = data['employees'] as List? ?? [];
    return list.map((json) => Employee.fromJson(json)).toList();
  }
}
