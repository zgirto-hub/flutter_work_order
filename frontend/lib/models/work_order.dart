import 'employee_assignment.dart';

class WorkOrder {
  final String jobNo;
  final String Title;
  final String status;
  final String description;
  final String location;
  final String type;
  final String dateCreated;
  final String dateModified;
  final String? closedAt;
  final String id;
  final String? createdBy;
  final String? createdByEmail;
  final String department;
  final String? mobileNumber;
  final List<EmployeeAssignment> assignedEmployees;

  const WorkOrder({
    required this.id,
    required this.jobNo,
    required this.Title,
    required this.status,
    required this.description,
    required this.location,
    required this.type,
    required this.dateCreated,
    required this.dateModified,
    this.closedAt,
    this.createdBy,
    this.createdByEmail,
    this.department = 'General',
    this.mobileNumber,
    this.assignedEmployees = const [],
  });

  factory WorkOrder.fromJson(Map<String, dynamic> json) {
    return WorkOrder(
      id: json['id'],
      jobNo: json['job_no'] ?? '',
      Title: json['title'] ?? '',
      status: json['status'] ?? 'Open',
      description: json['description'] ?? '',
      location: json['location'] ?? '',
      type: json['type'] ?? '',
      dateCreated: json['created_at']?.toString() ?? '',
      dateModified: json['updated_at']?.toString() ?? '',
      closedAt: json['closed_at']?.toString(),
      createdBy: json['created_by'],
      createdByEmail: json['created_by_email'] as String?,
      department: json['department'] ?? 'General',
      mobileNumber: json['mobile_number'],
      assignedEmployees: (json['work_order_assignments'] as List<dynamic>?)
              ?.map((assignment) => EmployeeAssignment.fromJson(assignment))
              .where((emp) => emp.id.isNotEmpty)
              .toList() ??
          [],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'title': Title,
      'description': description,
      'status': status,
      'location': location,
      'type': type,
      'department': department,
      'mobile_number': mobileNumber,
    };
  }
}
