import 'employee_assignment.dart';

class WorkOrder {
  final String id;
  final String jobNo;
  final String title;
  final String status;
  final String description;
  final String location;
  final String type;
  final String dateCreated;
  final String dateModified;
  final String? closedAt;
  final String? closedBy;
  final String? techNotes;
  final String? createdBy;
  final String? createdByEmail;
  final String department;
  final String? mobileNumber;
  final List<EmployeeAssignment> assignedEmployees;

  const WorkOrder({
    required this.id,
    required this.jobNo,
    required this.title,
    required this.status,
    required this.description,
    required this.location,
    required this.type,
    required this.dateCreated,
    required this.dateModified,
    this.closedAt,
    this.closedBy,
    this.techNotes,
    this.createdBy,
    this.createdByEmail,
    this.department = 'General',
    this.mobileNumber,
    this.assignedEmployees = const [],
  });

  factory WorkOrder.fromJson(Map<String, dynamic> json) {
    return WorkOrder(
      id: json['id'] ?? '',
      jobNo: json['job_no'] ?? '',
      title: json['title'] ?? '',
      status: json['status'] ?? 'Open',
      description: json['description'] ?? '',
      location: json['location'] ?? '',
      type: json['type'] ?? '',
      dateCreated: json['created_at']?.toString() ?? '',
      dateModified: json['updated_at']?.toString() ?? '',
      closedAt: json['closed_at']?.toString(),
      closedBy: json['closed_by'],
      techNotes: json['tech_notes'],
      createdBy: json['created_by'],
      createdByEmail: json['created_by_email'] as String?,
      department: json['department'] ?? 'General',
      mobileNumber: json['mobile_number'],
      assignedEmployees: (json['work_order_assignments'] as List<dynamic>?)
              ?.map((assignment) => EmployeeAssignment.fromJson(assignment as Map<String, dynamic>))
              .where((emp) => emp.id.isNotEmpty)
              .toList() ??
          [],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'job_no': jobNo,
      'title': title,
      'description': description,
      'status': status,
      'location': location,
      'type': type,
      'department': department,
      'mobile_number': mobileNumber,
      'created_by': createdBy,
      'assigned_fixer_ids': assignedEmployees.map((e) => e.id).toList(),
    };
  }

  WorkOrder copyWith({
    String? id,
    String? jobNo,
    String? title,
    String? status,
    String? description,
    String? location,
    String? type,
    String? dateCreated,
    String? dateModified,
    String? closedAt,
    String? closedBy,
    String? techNotes,
    String? createdBy,
    String? createdByEmail,
    String? department,
    String? mobileNumber,
    List<EmployeeAssignment>? assignedEmployees,
  }) {
    return WorkOrder(
      id: id ?? this.id,
      jobNo: jobNo ?? this.jobNo,
      title: title ?? this.title,
      status: status ?? this.status,
      description: description ?? this.description,
      location: location ?? this.location,
      type: type ?? this.type,
      dateCreated: dateCreated ?? this.dateCreated,
      dateModified: dateModified ?? this.dateModified,
      closedAt: closedAt ?? this.closedAt,
      closedBy: closedBy ?? this.closedBy,
      techNotes: techNotes ?? this.techNotes,
      createdBy: createdBy ?? this.createdBy,
      createdByEmail: createdByEmail ?? this.createdByEmail,
      department: department ?? this.department,
      mobileNumber: mobileNumber ?? this.mobileNumber,
      assignedEmployees: assignedEmployees ?? this.assignedEmployees,
    );
  }
}
