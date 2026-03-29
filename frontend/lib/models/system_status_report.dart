class SystemStatusReport {
  final String id;
  final String systemName;
  final String reportDate;
  final String notes;
  final String reportedBy;
  final String reportedByName;
  final String createdAt;
  final String? resolvedAt;
  final String? resolvedBy;

  const SystemStatusReport({
    required this.id,
    required this.systemName,
    required this.reportDate,
    this.notes = '',
    required this.reportedBy,
    this.reportedByName = '',
    required this.createdAt,
    this.resolvedAt,
    this.resolvedBy,
  });

  factory SystemStatusReport.fromJson(Map<String, dynamic> json) {
    return SystemStatusReport(
      id: json['id'] ?? '',
      systemName: json['system_name'] ?? '',
      reportDate: json['report_date'] ?? '',
      notes: json['notes'] ?? '',
      reportedBy: json['reported_by'] ?? '',
      reportedByName: json['reported_by_name'] ?? '',
      createdAt: json['created_at']?.toString() ?? '',
      resolvedAt: json['resolved_at']?.toString(),
      resolvedBy: json['resolved_by'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'system_name': systemName,
      'report_date': reportDate,
      'notes': notes,
      'reported_by': reportedBy,
      'reported_by_name': reportedByName,
    };
  }

  bool get isResolved => resolvedAt != null;
}

class SystemStatus {
  final String systemName;
  final String status;
  final SystemStatusReport? activeReport;

  const SystemStatus({
    required this.systemName,
    required this.status,
    this.activeReport,
  });

  factory SystemStatus.fromJson(Map<String, dynamic> json) {
    return SystemStatus(
      systemName: json['system_name'] ?? '',
      status: json['status'] ?? 'operational',
      activeReport: json['active_report'] != null
          ? SystemStatusReport.fromJson(json['active_report'])
          : null,
    );
  }

  bool get hasIssue => status == 'issue';
}

class SystemUptimeReport {
  final String systemName;
  final int totalDays;
  final int daysWithIssues;
  final double uptimePct;
  final double downtimePct;

  const SystemUptimeReport({
    required this.systemName,
    required this.totalDays,
    required this.daysWithIssues,
    required this.uptimePct,
    required this.downtimePct,
  });

  factory SystemUptimeReport.fromJson(Map<String, dynamic> json) {
    return SystemUptimeReport(
      systemName: json['system_name'] ?? '',
      totalDays: json['total_days'] ?? 0,
      daysWithIssues: json['days_with_issues'] ?? 0,
      uptimePct: (json['uptime_pct'] ?? 100).toDouble(),
      downtimePct: (json['downtime_pct'] ?? 0).toDouble(),
    );
  }
}
