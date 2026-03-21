import 'technician_assignment.dart';

class RecurringInspection {
  final String id;
  final String title;
  final String description;
  final String location;
  final String departmentId;
  final String? departmentName;
  final String frequency; // daily, weekly, monthly
  final int? dayOfWeek; // 0=Mon..6=Sun
  final int? dayOfMonth; // 1-31
  final String startDate;
  final String? endDate;
  final String nextDueDate;
  final bool isActive;
  final String? createdBy;
  final String? createdAt;
  final String? updatedAt;
  final List<TechnicianAssignment> assignees;

  const RecurringInspection({
    required this.id,
    required this.title,
    this.description = '',
    this.location = '',
    required this.departmentId,
    this.departmentName,
    required this.frequency,
    this.dayOfWeek,
    this.dayOfMonth,
    required this.startDate,
    this.endDate,
    required this.nextDueDate,
    this.isActive = true,
    this.createdBy,
    this.createdAt,
    this.updatedAt,
    this.assignees = const [],
  });

  factory RecurringInspection.fromJson(Map<String, dynamic> json) {
    String? deptName;
    if (json['departments'] is Map<String, dynamic>) {
      deptName = json['departments']['name'];
    }

    final assigneeList = (json['recurring_inspection_assignees'] as List<dynamic>?)
        ?.map((a) {
          if (a is Map<String, dynamic> && a['users'] is Map<String, dynamic>) {
            return TechnicianAssignment(
              id: a['users']['id'] ?? '',
              fullName: a['users']['full_name'] ?? '',
              email: a['users']['email'] ?? '',
            );
          }
          return null;
        })
        .where((t) => t != null && t.id.isNotEmpty)
        .cast<TechnicianAssignment>()
        .toList() ?? [];

    return RecurringInspection(
      id: json['id'] ?? '',
      title: json['title'] ?? '',
      description: json['description'] ?? '',
      location: json['location'] ?? '',
      departmentId: json['department_id'] ?? '',
      departmentName: deptName,
      frequency: json['frequency'] ?? 'daily',
      dayOfWeek: json['day_of_week'],
      dayOfMonth: json['day_of_month'],
      startDate: json['start_date'] ?? '',
      endDate: json['end_date'],
      nextDueDate: json['next_due_date'] ?? '',
      isActive: json['is_active'] ?? true,
      createdBy: json['created_by'],
      createdAt: json['created_at']?.toString(),
      updatedAt: json['updated_at']?.toString(),
      assignees: assigneeList,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'title': title,
      'description': description,
      'location': location,
      'department_id': departmentId,
      'frequency': frequency,
      'day_of_week': dayOfWeek,
      'day_of_month': dayOfMonth,
      'start_date': startDate,
      'end_date': endDate,
      'is_active': isActive,
      'assigned_fixer_ids': assignees.map((e) => e.id).toList(),
    };
  }

  String get frequencyLabel {
    switch (frequency) {
      case 'daily':
        return 'Daily';
      case 'weekly':
        return 'Weekly';
      case 'monthly':
        return 'Monthly';
      default:
        return frequency;
    }
  }

  String get scheduleDescription {
    switch (frequency) {
      case 'daily':
        return 'Every day';
      case 'weekly':
        final days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
        final day = (dayOfWeek != null && dayOfWeek! >= 0 && dayOfWeek! < 7)
            ? days[dayOfWeek!]
            : 'Mon';
        return 'Every $day';
      case 'monthly':
        final dom = dayOfMonth ?? 1;
        return 'Every month on day $dom';
      default:
        return frequency;
    }
  }
}
