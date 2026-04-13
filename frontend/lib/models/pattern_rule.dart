class PatternRule {
  final String id;
  final String name;
  final String? description;
  final String severity;
  final String detectionType;
  final int? thresholdCount;
  final int? thresholdDays;
  final String? targetField;
  final String? groupByField;
  final bool enabled;
  final bool isBuiltIn;
  final DateTime createdAt;
  final DateTime updatedAt;

  PatternRule({
    required this.id,
    required this.name,
    this.description,
    required this.severity,
    required this.detectionType,
    this.thresholdCount,
    this.thresholdDays,
    this.targetField,
    this.groupByField,
    required this.enabled,
    required this.isBuiltIn,
    required this.createdAt,
    required this.updatedAt,
  });

  factory PatternRule.fromJson(Map<String, dynamic> json) {
    return PatternRule(
      id: json['id'] as String,
      name: json['name'] as String,
      description: json['description'] as String?,
      severity: json['severity'] as String,
      detectionType: json['detection_type'] as String,
      thresholdCount: json['threshold_count'] as int?,
      thresholdDays: json['threshold_days'] as int?,
      targetField: json['target_field'] as String?,
      groupByField: json['group_by_field'] as String?,
      enabled: json['enabled'] as bool,
      isBuiltIn: json['is_built_in'] as bool,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'severity': severity,
      'detection_type': detectionType,
      'threshold_count': thresholdCount,
      'threshold_days': thresholdDays,
      'target_field': targetField,
      'group_by_field': groupByField,
      'enabled': enabled,
      'is_built_in': isBuiltIn,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  PatternRule copyWith({
    String? id,
    String? name,
    String? description,
    String? severity,
    String? detectionType,
    int? thresholdCount,
    int? thresholdDays,
    String? targetField,
    String? groupByField,
    bool? enabled,
    bool? isBuiltIn,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return PatternRule(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      severity: severity ?? this.severity,
      detectionType: detectionType ?? this.detectionType,
      thresholdCount: thresholdCount ?? this.thresholdCount,
      thresholdDays: thresholdDays ?? this.thresholdDays,
      targetField: targetField ?? this.targetField,
      groupByField: groupByField ?? this.groupByField,
      enabled: enabled ?? this.enabled,
      isBuiltIn: isBuiltIn ?? this.isBuiltIn,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
