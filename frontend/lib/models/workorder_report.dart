class WorkOrderReport {
  final String title;
  final String description;
  final DateTime modifiedDate;
  final String location;

  WorkOrderReport({
    required this.title,
    this.description = '',
    required this.modifiedDate,
    required this.location,
  });

  factory WorkOrderReport.fromJson(Map<String, dynamic> json) {
    return WorkOrderReport(
      title: json['title'] ?? '',
      description: json['description'] ?? '',
      location: json['location'] ?? '',
      modifiedDate: DateTime.parse(json['closed_at']),
    );
  }
}
