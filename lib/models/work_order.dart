class WorkOrder {
  final String jobNo;
  final String client;
  final String status;
  final String description;

  final String location;        // ✅ NEW
  final String type;            // ✅ NEW
  final String dateCreated;     // ✅ NEW
  final String dateModified;    // ✅ NEW

  const WorkOrder({
    required this.jobNo,
    required this.client,
    required this.status,
    required this.description,
    required this.location,
    required this.type,
    required this.dateCreated,
    required this.dateModified,
  });
}