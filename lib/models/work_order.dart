class WorkOrder {
  final String jobNo;
  final String client;
  final String status;
  final String description;
  final String location;
  final String type;
  final String dateCreated;
  final String dateModified;
  final String id;

  const WorkOrder({
    required this.id,
    required this.jobNo,
    required this.client,
    required this.status,
    required this.description,
    required this.location,
    required this.type,
    required this.dateCreated,
    required this.dateModified,
  });

  factory WorkOrder.fromJson(Map<String, dynamic> json) {
    return WorkOrder(
      id: json['id'],
      jobNo: json['job_no'] ?? '',
      client: json['title'] ?? '',
      status: json['status'] ?? 'Open',
      description: json['description'] ?? '',
      location: json['location'] ?? '',
      type: json['type'] ?? '',
      dateCreated: json['created_at']?.toString() ?? '',
      dateModified: json['updated_at']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'title': client,
      'description': description,
      'status': status,
      'location': location,
      'type': type,
    };
  }
}
