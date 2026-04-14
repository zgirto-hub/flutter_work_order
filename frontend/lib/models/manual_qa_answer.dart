import 'manual_source.dart';

class RetrievalInfo {
  final String? detectedSystem;
  final List<String> filteredManualIds;
  final bool filterApplied;
  final String? fallbackReason;

  const RetrievalInfo({
    this.detectedSystem,
    this.filteredManualIds = const [],
    this.filterApplied = false,
    this.fallbackReason,
  });

  factory RetrievalInfo.fromJson(Map<String, dynamic> json) {
    return RetrievalInfo(
      detectedSystem: json['detected_system'] as String?,
      filteredManualIds: (json['filtered_manual_ids'] as List?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      filterApplied: json['filter_applied'] as bool? ?? false,
      fallbackReason: json['fallback_reason'] as String?,
    );
  }
}

class ManualConsulted {
  final String id;
  final String title;

  const ManualConsulted({required this.id, required this.title});

  factory ManualConsulted.fromJson(Map<String, dynamic> json) {
    return ManualConsulted(
      id: json['id'] ?? '',
      title: json['title'] ?? '',
    );
  }
}

class VerifiedSource {
  final String validatedQaId;
  final String validatedBy;
  final DateTime validatedAt;
  final double similarity;

  const VerifiedSource({
    required this.validatedQaId,
    required this.validatedBy,
    required this.validatedAt,
    required this.similarity,
  });

  factory VerifiedSource.fromJson(Map<String, dynamic> json) {
    return VerifiedSource(
      validatedQaId: json['validated_qa_id'] ?? '',
      validatedBy: json['validated_by'] ?? '',
      validatedAt: json['validated_at'] != null
          ? DateTime.parse(json['validated_at'])
          : DateTime.now(),
      similarity: (json['similarity'] as num?)?.toDouble() ?? 0.0,
    );
  }
}

class ManualQaAnswer {
  final String answer;
  final List<ManualSource> sources;
  final bool grounded;
  final String? model;
  final double? durationSeconds;
  final String? sessionSummary;
  final List<ManualConsulted> manualsConsulted;
  final bool hasConflicts;
  final bool agentic;
  final List<Map<String, dynamic>> toolsUsed;
  final bool isVerified;
  final VerifiedSource? verifiedSource;
  final RetrievalInfo? retrievalInfo;

  const ManualQaAnswer({
    required this.answer,
    required this.sources,
    required this.grounded,
    this.model,
    this.durationSeconds,
    this.sessionSummary,
    this.manualsConsulted = const [],
    this.hasConflicts = false,
    this.agentic = false,
    this.toolsUsed = const [],
    this.isVerified = false,
    this.verifiedSource,
    this.retrievalInfo,
  });

  factory ManualQaAnswer.fromJson(Map<String, dynamic> json) {
    final sourcesList = <ManualSource>[];
    if (json['sources'] != null) {
      for (var source in json['sources']) {
        sourcesList.add(ManualSource.fromJson(source));
      }
    }
    final consultedList = <ManualConsulted>[];
    if (json['manuals_consulted'] != null) {
      for (var mc in json['manuals_consulted']) {
        consultedList.add(ManualConsulted.fromJson(mc));
      }
    }
    VerifiedSource? verifiedSource;
    if (json['verified_source'] != null) {
      verifiedSource = VerifiedSource.fromJson(json['verified_source']);
    }
    RetrievalInfo? retrievalInfo;
    if (json['retrieval_info'] != null) {
      retrievalInfo = RetrievalInfo.fromJson(
        Map<String, dynamic>.from(json['retrieval_info'] as Map),
      );
    }
    return ManualQaAnswer(
      answer: json['answer'] ?? '',
      sources: sourcesList,
      grounded: json['grounded'] ?? false,
      model: json['model'],
      durationSeconds: (json['duration_seconds'] as num?)?.toDouble(),
      sessionSummary: json['session_summary'],
      manualsConsulted: consultedList,
      hasConflicts: json['has_conflicts'] ?? false,
      agentic: json['agentic'] ?? false,
      toolsUsed: (json['tools_used'] as List<dynamic>?)
              ?.map((e) => Map<String, dynamic>.from(e as Map))
              .toList() ??
          [],
      isVerified: json['is_verified'] ?? false,
      verifiedSource: verifiedSource,
      retrievalInfo: retrievalInfo,
    );
  }

  String get durationFormatted {
    if (durationSeconds == null) return '';
    final total = durationSeconds!.round();
    final m = total ~/ 60;
    final s = total % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }
}
