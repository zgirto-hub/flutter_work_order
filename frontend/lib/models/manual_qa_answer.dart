import 'manual_source.dart';

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

class ManualQaAnswer {
  final String answer;
  final List<ManualSource> sources;
  final bool grounded;
  final String? model;
  final double? durationSeconds;
  final String? sessionSummary;
  final List<ManualConsulted> manualsConsulted;
  final bool hasConflicts;

  const ManualQaAnswer({
    required this.answer,
    required this.sources,
    required this.grounded,
    this.model,
    this.durationSeconds,
    this.sessionSummary,
    this.manualsConsulted = const [],
    this.hasConflicts = false,
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
    return ManualQaAnswer(
      answer: json['answer'] ?? '',
      sources: sourcesList,
      grounded: json['grounded'] ?? false,
      model: json['model'],
      durationSeconds: (json['duration_seconds'] as num?)?.toDouble(),
      sessionSummary: json['session_summary'],
      manualsConsulted: consultedList,
      hasConflicts: json['has_conflicts'] ?? false,
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
