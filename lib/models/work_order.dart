class WorkOrder {
  final String jobNo;
  final String Title;
  final String status;
  final String description;
  final String location;
  final String type;
  final String dateCreated;
  final String dateModified;
  final String id;
  final String? createdBy;

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
    this.createdBy,
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
      createdBy: json['created_by'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'title': Title,
      'description': description,
      'status': status,
      'location': location,
      'type': type,
    };
  }
}
