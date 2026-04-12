import 'manual_source.dart';

class ManualQaAnswer {
  final String answer;
  final List<ManualSource> sources;
  final bool grounded;
  final String? model;
  final double? durationSeconds;

  const ManualQaAnswer({
    required this.answer,
    required this.sources,
    required this.grounded,
    this.model,
    this.durationSeconds,
  });

  factory ManualQaAnswer.fromJson(Map<String, dynamic> json) {
    final sourcesList = <ManualSource>[];
    if (json['sources'] != null) {
      for (var source in json['sources']) {
        sourcesList.add(ManualSource.fromJson(source));
      }
    }
    return ManualQaAnswer(
      answer: json['answer'] ?? '',
      sources: sourcesList,
      grounded: json['grounded'] ?? false,
      model: json['model'],
      durationSeconds: (json['duration_seconds'] as num?)?.toDouble(),
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
