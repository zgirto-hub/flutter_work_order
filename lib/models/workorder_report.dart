class WorkOrderReport {
  final String title;
  final DateTime modifiedDate;
  final String location;

  WorkOrderReport({
    required this.title,
    required this.modifiedDate,
    required this.location,
  });

  factory WorkOrderReport.fromJson(Map<String, dynamic> json) {
  return WorkOrderReport(
    title: json['title'] ?? '',
    location: json['location'] ?? '',
    modifiedDate: DateTime.parse(json['updated_at']),
  );
}
}