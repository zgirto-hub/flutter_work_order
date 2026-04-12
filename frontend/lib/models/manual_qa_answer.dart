import 'manual_source.dart';

class ManualQaAnswer {
  final String answer;
  final List<ManualSource> sources;
  final bool grounded;

  const ManualQaAnswer({
    required this.answer,
    required this.sources,
    required this.grounded,
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
    );
  }
}
