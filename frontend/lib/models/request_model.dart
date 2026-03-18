class RequestModel {
  final String id;
  final String title;
  final String description;
  final String status; // 'Pending' | 'In Progress' | 'Closed'
  final String createdBy; // email
  final String requesterName;
  final String location;
  final DateTime createdAt;
  final String? closedBy;
  final DateTime? closedAt;
  final String? techNotes;

  RequestModel({
    required this.id,
    required this.title,
    required this.description,
    required this.status,
    required this.createdBy,
    required this.requesterName,
    required this.location,
    required this.createdAt,
    this.closedBy,
    this.closedAt,
    this.techNotes,
  });

  factory RequestModel.fromJson(Map<String, dynamic> json) => RequestModel(
        id: json['id'] as String,
        title: json['title'] as String,
        description: json['description'] as String? ?? '',
        status: json['status'] as String? ?? 'Pending',
        createdBy: json['created_by'] as String,
        requesterName: json['requester_name'] as String? ?? '',
        location: json['location'] as String? ?? '',
        createdAt: DateTime.parse(json['created_at'] as String),
        closedBy: json['closed_by'] as String?,
        closedAt: json['closed_at'] != null
            ? DateTime.parse(json['closed_at'] as String)
            : null,
        techNotes: json['tech_notes'] as String?,
      );
}
