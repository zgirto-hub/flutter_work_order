class AppNotification {
  final String id;
  final String? userId;
  final String userEmail;
  final String kind;
  final String title;
  final String body;
  final Map<String, dynamic> data;
  final String sourceType;
  final String sourceId;
  final DateTime? readAt;
  final DateTime createdAt;

  const AppNotification({
    required this.id,
    this.userId,
    required this.userEmail,
    required this.kind,
    required this.title,
    required this.body,
    required this.data,
    required this.sourceType,
    required this.sourceId,
    required this.readAt,
    required this.createdAt,
  });

  factory AppNotification.fromJson(Map<String, dynamic> json) {
    final rawData = json['data'];
    return AppNotification(
      id: (json['id'] ?? '').toString(),
      userId: json['user_id']?.toString(),
      userEmail: (json['user_email'] ?? '').toString(),
      kind: (json['kind'] ?? '').toString(),
      title: (json['title'] ?? '').toString(),
      body: (json['body'] ?? '').toString(),
      data: rawData is Map<String, dynamic>
          ? rawData
          : Map<String, dynamic>.from(rawData ?? {}),
      sourceType: (json['source_type'] ?? '').toString(),
      sourceId: (json['source_id'] ?? '').toString(),
      readAt: json['read_at'] == null
          ? null
          : DateTime.tryParse(json['read_at'].toString()),
      createdAt: DateTime.tryParse(json['created_at'].toString()) ?? DateTime.now(),
    );
  }

  bool get isUnread => readAt == null;
}
