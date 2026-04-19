class SystemStatusReport {
  final String id;
  final String systemName;
  final String? assetId;
  final String? assetName;
  final String reportDate;
  final String notes;
  final String reportedBy;
  final String reportedByName;
  final String createdAt;
  final String? resolvedAt;
  final String? resolvedBy;
  final String resolvedNotes;

  const SystemStatusReport({
    required this.id,
    required this.systemName,
    this.assetId,
    this.assetName,
    required this.reportDate,
    this.notes = '',
    required this.reportedBy,
    this.reportedByName = '',
    required this.createdAt,
    this.resolvedAt,
    this.resolvedBy,
    this.resolvedNotes = '',
  });

  factory SystemStatusReport.fromJson(Map<String, dynamic> json) {
    return SystemStatusReport(
      id: json['id'] ?? '',
      systemName: json['system_name'] ?? '',
      assetId: json['asset_id'],
      assetName: json['asset_name'],
      reportDate: json['report_date'] ?? '',
      notes: json['notes'] ?? '',
      reportedBy: json['reported_by'] ?? '',
      reportedByName: json['reported_by_name'] ?? '',
      createdAt: json['created_at']?.toString() ?? '',
      resolvedAt: json['resolved_at']?.toString(),
      resolvedBy: json['resolved_by'],
      resolvedNotes: json['resolved_notes'] ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'system_name': systemName,
      if (assetId != null) 'asset_id': assetId,
      'report_date': reportDate,
      'notes': notes,
      'reported_by': reportedBy,
      'reported_by_name': reportedByName,
    };
  }

  bool get isResolved => resolvedAt != null;
}

class AssetStatusEntry {
  final String assetId;
  final String assetName;
  final String role;
  final String site;
  final String status;
  final SystemStatusReport? activeReport;

  const AssetStatusEntry({
    required this.assetId,
    required this.assetName,
    required this.role,
    required this.site,
    required this.status,
    this.activeReport,
  });

  factory AssetStatusEntry.fromJson(Map<String, dynamic> json) {
    return AssetStatusEntry(
      assetId: json['asset_id'] ?? '',
      assetName: json['asset_name'] ?? '',
      role: json['role'] ?? '',
      site: json['site'] ?? '',
      status: json['status'] ?? 'operational',
      activeReport: json['active_report'] != null
          ? SystemStatusReport.fromJson(json['active_report'])
          : null,
    );
  }

  bool get hasIssue => status == 'issue';
}

class SystemAssetsResponse {
  final String systemId;
  final String systemName;
  final List<AssetStatusEntry> assets;

  const SystemAssetsResponse({
    required this.systemId,
    required this.systemName,
    required this.assets,
  });

  factory SystemAssetsResponse.fromJson(Map<String, dynamic> json) {
    return SystemAssetsResponse(
      systemId: json['system_id'] ?? '',
      systemName: json['system_name'] ?? '',
      assets: (json['assets'] as List? ?? [])
          .map((j) => AssetStatusEntry.fromJson(j))
          .toList(),
    );
  }
}

class SystemStatus {
  final String systemId;
  final String systemName;
  final String status;
  final SystemStatusReport? activeReport;
  final int assetIssuesCount;

  const SystemStatus({
    required this.systemId,
    required this.systemName,
    required this.status,
    this.activeReport,
    this.assetIssuesCount = 0,
  });

  factory SystemStatus.fromJson(Map<String, dynamic> json) {
    return SystemStatus(
      systemId: json['system_id'] ?? '',
      systemName: json['system_name'] ?? '',
      status: json['status'] ?? 'operational',
      activeReport: json['active_report'] != null
          ? SystemStatusReport.fromJson(json['active_report'])
          : null,
      assetIssuesCount: json['asset_issues_count'] ?? 0,
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
  final List<AssetUptimeReport> assets;

  const SystemUptimeReport({
    required this.systemName,
    required this.totalDays,
    required this.daysWithIssues,
    required this.uptimePct,
    required this.downtimePct,
    this.assets = const [],
  });

  factory SystemUptimeReport.fromJson(Map<String, dynamic> json) {
    return SystemUptimeReport(
      systemName: json['system_name'] ?? '',
      totalDays: json['total_days'] ?? 0,
      daysWithIssues: json['days_with_issues'] ?? 0,
      uptimePct: (json['uptime_pct'] ?? 100).toDouble(),
      downtimePct: (json['downtime_pct'] ?? 0).toDouble(),
      assets: (json['assets'] as List? ?? [])
          .map((j) => AssetUptimeReport.fromJson(j))
          .toList(),
    );
  }
}

class AssetUptimeReport {
  final String assetId;
  final String assetName;
  final String role;
  final String site;
  final int totalDays;
  final int daysWithIssues;
  final double uptimePct;
  final double downtimePct;

  const AssetUptimeReport({
    required this.assetId,
    required this.assetName,
    required this.role,
    required this.site,
    required this.totalDays,
    required this.daysWithIssues,
    required this.uptimePct,
    required this.downtimePct,
  });

  factory AssetUptimeReport.fromJson(Map<String, dynamic> json) {
    return AssetUptimeReport(
      assetId: json['asset_id'] ?? '',
      assetName: json['asset_name'] ?? '',
      role: json['role'] ?? '',
      site: json['site'] ?? '',
      totalDays: json['total_days'] ?? 0,
      daysWithIssues: json['days_with_issues'] ?? 0,
      uptimePct: (json['uptime_pct'] ?? 100).toDouble(),
      downtimePct: (json['downtime_pct'] ?? 0).toDouble(),
    );
  }
}
