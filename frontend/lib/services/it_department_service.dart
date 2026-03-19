import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config.dart';

class ItDepartmentService {
  Future<Map<String, dynamic>> getItReporterDepartments(String email) async {
    final res = await http.get(
      Uri.parse('${AppConfig.baseUrl}/it-department-reporters?email=${Uri.encodeComponent(email)}'),
    );
    if (res.statusCode == 200) {
      return jsonDecode(res.body);
    }
    return {'it_department': null, 'reporter_departments': []};
  }

  Future<Map<String, dynamic>> getAllMappings() async {
    final res = await http.get(
      Uri.parse('${AppConfig.baseUrl}/it-department-reporters/all'),
    );
    if (res.statusCode == 200) {
      return jsonDecode(res.body);
    }
    return {'mappings': []};
  }

  Future<bool> assignReporter(String itDepartment, String reporterDepartment) async {
    final res = await http.post(
      Uri.parse('${AppConfig.baseUrl}/it-department-reporters'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'it_department': itDepartment,
        'reporter_department': reporterDepartment,
      }),
    );
    return res.statusCode == 200;
  }

  Future<bool> removeReporter(String itDepartment, String reporterDepartment) async {
    final res = await http.delete(
      Uri.parse('${AppConfig.baseUrl}/it-department-reporters?it_department=${Uri.encodeComponent(itDepartment)}&reporter_department=${Uri.encodeComponent(reporterDepartment)}'),
    );
    return res.statusCode == 200;
  }

  Future<bool> updateEmployeeItTeam(String email, String itTeam) async {
    final res = await http.patch(
      Uri.parse('${AppConfig.baseUrl}/employees/${Uri.encodeComponent(email)}/it-team?it_team=${Uri.encodeComponent(itTeam)}'),
    );
    return res.statusCode == 200;
  }
}
