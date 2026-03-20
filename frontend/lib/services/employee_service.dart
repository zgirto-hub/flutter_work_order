import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/user.dart';
import '../config.dart';

class EmployeeService {
  Future<List<AppUser>> fetchEmployees({bool techOnly = false}) async {
    final uri = Uri.parse('${AppConfig.baseUrl}/employees')
        .replace(queryParameters: techOnly ? {'tech': 'true'} : null);
    final res = await http.get(uri);
    if (res.statusCode != 200) {
      throw Exception('Failed to fetch employees');
    }
    final data = jsonDecode(res.body);
    final list = data['employees'] as List? ?? [];
    return list.map((json) => AppUser.fromEmployeesJson(json)).toList();
  }
}
