import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:work_order/models/manual_qa_answer.dart';
import 'package:work_order/screens/manual_assistant/widgets/answer_card.dart';

Widget _wrap(Widget child) {
  return MaterialApp(
    home: Scaffold(body: child),
  );
}

void main() {
  testWidgets('shows filter chip when retrieval filter applied',
      (tester) async {
    const answer = ManualQaAnswer(
      answer: 'Use the documented backup steps.',
      sources: [],
      grounded: true,
      manualsConsulted: [
        ManualConsulted(id: '1', title: 'CADAS-ATS Operations Manual'),
      ],
      retrievalInfo: RetrievalInfo(
        detectedSystem: 'CADAS-ATS',
        filteredManualIds: ['1'],
        filterApplied: true,
      ),
    );

    await tester.pumpWidget(_wrap(const AnswerCard(answer: answer)));

    expect(find.text('Filtered to: CADAS-ATS'), findsOneWidget);
  });

  testWidgets('hides filter chip when retrieval filter not applied', (
    tester,
  ) async {
    const answer = ManualQaAnswer(
      answer: 'General maintenance guidance.',
      sources: [],
      grounded: true,
      manualsConsulted: [
        ManualConsulted(id: '1', title: 'General Maintenance Manual'),
      ],
      retrievalInfo: RetrievalInfo(
        detectedSystem: 'CADAS-ATS',
        filterApplied: false,
      ),
    );

    await tester.pumpWidget(_wrap(const AnswerCard(answer: answer)));

    expect(find.textContaining('Filtered to:'), findsNothing);
  });
}
