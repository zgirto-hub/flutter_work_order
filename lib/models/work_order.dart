class WorkOrder {
  final String jobNo;
  final String client;
  final String status;
  final String description;

  const WorkOrder({
    required this.jobNo,
    required this.client,
    required this.status,
    required this.description,
  });
}