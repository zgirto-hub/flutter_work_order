class ActivityLogEntry {
  final String id;
  final String userEmail;
  final String userName;
  final String category;  // 'work_order' | 'file' | 'folder' | 'request' | 'auth'
  final String action;    // 'created' | 'updated' | 'deleted' | 'uploaded' | 'shared' | 'closed' | 'signed_in'
  final String? targetLabel;
  final String? targetId;
  final String? detail;
  final DateTime createdAt;

  const ActivityLogEntry({
    required this.id,
    required this.userEmail,
    required this.userName,
    required this.category,
    required this.action,
    this.targetLabel,
    this.targetId,
    this.detail,
    required this.createdAt,
  });

  factory ActivityLogEntry.fromJson(Map<String, dynamic> json) {
    return ActivityLogEntry(
      id: json['id'] as String,
      userEmail: json['user_email'] as String,
      userName: json['user_name'] as String,
      category: json['category'] as String,
      action: json['action'] as String,
      targetLabel: json['target_label'] as String?,
      targetId: json['target_id'] as String?,
      detail: json['detail'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  String get initials {
    if (userName.length >= 2) return userName.substring(0, 2).toUpperCase();
    return userName.toUpperCase();
  }

  String get formattedTime {
    return '${createdAt.hour.toString().padLeft(2, '0')}:${createdAt.minute.toString().padLeft(2, '0')}';
  }

  String get formattedDate {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final entryDay = DateTime(createdAt.year, createdAt.month, createdAt.day);
    if (entryDay == today) return 'Today';
    if (entryDay == yesterday) return 'Yesterday';
    return '${createdAt.day}/${createdAt.month}/${createdAt.year}';
  }

  // Human-readable action label
  String get actionLabel {
    switch (action) {
      case 'created':         return 'Created';
      case 'updated':         return 'Updated';
      case 'deleted':         return 'Deleted';
      case 'uploaded':        return 'Uploaded';
      case 'shared':          return 'Shared';
      case 'closed':          return 'Closed';
      case 'signed_in':       return 'Signed in';
      case 'signed_out':      return 'Signed out';
      case 'account_created': return 'Account created';
      default:                return action;
    }
  }

  // Description text shown in the timeline
  String get description {
    switch (action) {
      case 'created':   return 'Created $category'.replaceAll('_', ' ');
      case 'updated':   return 'Updated $category'.replaceAll('_', ' ');
      case 'deleted':   return 'Deleted $category'.replaceAll('_', ' ');
      case 'uploaded':  return 'Uploaded file';
      case 'shared':    return 'Shared file';
      case 'closed':    return 'Closed $category'.replaceAll('_', ' ');
      case 'signed_in':  return 'Signed in';
      case 'signed_out': return 'Signed out';
      default:           return actionLabel;
    }
  }
}
