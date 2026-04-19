class RagDiagnosticEntry {
  final String id;
  final DateTime createdAt;
  final String userEmail;
  final String source;
  final String questionRaw;
  final String decision;
  final String reasonCode;
  final String? reasonNote;
  final String? providerUsed;
  final Map<String, dynamic> latencyBreakdown;
  final Map<String, dynamic>? pipelineStages;
  final Map<String, dynamic>? thresholds;

  RagDiagnosticEntry({
    required this.id,
    required this.createdAt,
    required this.userEmail,
    required this.source,
    required this.questionRaw,
    required this.decision,
    required this.reasonCode,
    this.reasonNote,
    this.providerUsed,
    required this.latencyBreakdown,
    this.pipelineStages,
    this.thresholds,
  });

  factory RagDiagnosticEntry.fromListJson(Map<String, dynamic> json) {
    return RagDiagnosticEntry(
      id: json['id'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
      userEmail: json['user_email'] as String,
      source: json['source'] as String,
      questionRaw: json['question_raw'] as String,
      decision: json['decision'] as String,
      reasonCode: json['reason_code'] as String,
      reasonNote: json['reason_note'] as String?,
      providerUsed: json['provider_used'] as String?,
      latencyBreakdown: (json['latency_breakdown'] as Map<String, dynamic>?) ?? {},
      pipelineStages: null,
      thresholds: null,
    );
  }

  factory RagDiagnosticEntry.fromDetailJson(Map<String, dynamic> json) {
    return RagDiagnosticEntry(
      id: json['id'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
      userEmail: json['user_email'] as String,
      source: json['source'] as String,
      questionRaw: json['question_raw'] as String,
      decision: json['decision'] as String,
      reasonCode: json['reason_code'] as String,
      reasonNote: json['reason_note'] as String?,
      providerUsed: json['provider_used'] as String?,
      latencyBreakdown: (json['latency_breakdown'] as Map<String, dynamic>?) ?? {},
      pipelineStages: json['pipeline_stages'] as Map<String, dynamic>?,
      thresholds: json['thresholds'] as Map<String, dynamic>?,
    );
  }

  String get totalMs {
    final ms = latencyBreakdown['total_ms'];
    if (ms is num) return ms.round().toString();
    return '-';
  }
}