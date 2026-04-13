class PatternAlert {
  final String id;
  final String ruleId;
  final String? ruleName;
  final List<String> workOrderIds;
  final String? equipmentId;
  final String? faultType;
  final String? technicianId;
  final String? system;
  final String severity;
  final String status;
  final String message;
  final DateTime detectedAt;
  final DateTime updatedAt;

  PatternAlert({
    required this.id,
    required this.ruleId,
    this.ruleName,
    required this.workOrderIds,
    this.equipmentId,
    this.faultType,
    this.technicianId,
    this.system,
    required this.severity,
    required this.status,
    required this.message,
    required this.detectedAt,
    required this.updatedAt,
  });

  factory PatternAlert.fromJson(Map<String, dynamic> json) {
    return PatternAlert(
      id: json['id'] as String,
      ruleId: json['rule_id'] as String,
      ruleName: json['rule_name'] as String?,
      workOrderIds: (json['work_order_ids'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
      equipmentId: json['equipment_id'] as String?,
      faultType: json['fault_type'] as String?,
      technicianId: json['technician_id'] as String?,
      system: json['system'] as String?,
      severity: json['severity'] as String,
      status: json['status'] as String,
      message: json['message'] as String,
      detectedAt: DateTime.parse(json['detected_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'rule_id': ruleId,
      'rule_name': ruleName,
      'work_order_ids': workOrderIds,
      'equipment_id': equipmentId,
      'fault_type': faultType,
      'technician_id': technicianId,
      'system': system,
      'severity': severity,
      'status': status,
      'message': message,
      'detected_at': detectedAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  PatternAlert copyWith({
    String? id,
    String? ruleId,
    String? ruleName,
    List<String>? workOrderIds,
    String? equipmentId,
    String? faultType,
    String? technicianId,
    String? system,
    String? severity,
    String? status,
    String? message,
    DateTime? detectedAt,
    DateTime? updatedAt,
  }) {
    return PatternAlert(
      id: id ?? this.id,
      ruleId: ruleId ?? this.ruleId,
      ruleName: ruleName ?? this.ruleName,
      workOrderIds: workOrderIds ?? this.workOrderIds,
      equipmentId: equipmentId ?? this.equipmentId,
      faultType: faultType ?? this.faultType,
      technicianId: technicianId ?? this.technicianId,
      system: system ?? this.system,
      severity: severity ?? this.severity,
      status: status ?? this.status,
      message: message ?? this.message,
      detectedAt: detectedAt ?? this.detectedAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
