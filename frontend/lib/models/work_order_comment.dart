class WorkOrderComment {
  final String id;
  final String workOrderId;
  final String authorEmail;
  final String authorName;
  final String body;
  final String type; // 'comment' | 'status_change' | 'system'
  final Map<String, dynamic>? meta;
  final DateTime createdAt;

  const WorkOrderComment({
    required this.id,
    required this.workOrderId,
    required this.authorEmail,
    required this.authorName,
    required this.body,
    required this.type,
    this.meta,
    required this.createdAt,
  });

  factory WorkOrderComment.fromJson(Map<String, dynamic> json) {
    return WorkOrderComment(
      id: json['id'] as String,
      workOrderId: json['work_order_id'] as String,
      authorEmail: json['author_email'] as String,
      authorName: json['author_name'] as String,
      body: json['body'] as String,
      type: json['type'] as String? ?? 'comment',
      meta: json['meta'] as Map<String, dynamic>?,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  String get initials {
    final parts = authorName.trim().split(' ');
    if (parts.length >= 2) return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    if (authorName.length >= 2) return authorName.substring(0, 2).toUpperCase();
    return authorName.toUpperCase();
  }

  String get formattedTime {
    final now = DateTime.now();
    final diff = now.difference(createdAt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    return '${createdAt.day}/${createdAt.month}/${createdAt.year}';
  }
}
