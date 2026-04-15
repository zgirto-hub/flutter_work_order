import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:work_order/models/manual_qa_answer.dart';
import 'package:work_order/models/latency_breakdown.dart';
import 'package:work_order/screens/manual_assistant/widgets/answer_card.dart';

void main() {
  group('AnswerCard latency display', () {
    testWidgets('full breakdown shows provider, generator, pipeline',
        (tester) async {
      final answer = ManualQaAnswer(
        answer: 'Test answer',
        sources: [],
        grounded: true,
        providerDisplayName: 'Groq (Llama 3.3 70B)',
        latencyBreakdown: LatencyBreakdown(
          embedMs: 98,
          hydeMs: 3412,
          rewriteMs: 201,
          retrievalMs: 387,
          rerankMs: 176,
          generatorMs: 1180,
          totalMs: 5571,
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AnswerCard(answer: answer, questionText: 'test?'),
          ),
        ),
      );

      expect(find.textContaining('Groq'), findsOneWidget);
      expect(find.textContaining('1.2s'), findsOneWidget);
      expect(find.textContaining('5.6s'), findsOneWidget);
      expect(find.byIcon(Icons.expand_more), findsOneWidget);
    });

    testWidgets('generator null shows pipeline only', (tester) async {
      final answer = ManualQaAnswer(
        answer: 'Hi!',
        sources: [],
        grounded: false,
        latencyBreakdown: LatencyBreakdown(
          embedMs: null,
          hydeMs: null,
          rewriteMs: null,
          retrievalMs: null,
          rerankMs: null,
          generatorMs: null,
          totalMs: 2,
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AnswerCard(answer: answer, questionText: 'hi'),
          ),
        ),
      );

      expect(find.textContaining('pipeline'), findsOneWidget);
      expect(find.byIcon(Icons.expand_more), findsOneWidget);
    });

    testWidgets('latency null renders without error', (tester) async {
      final answer = ManualQaAnswer(
        answer: 'Test answer',
        sources: [],
        grounded: true,
        model: 'Ollama',
        providerDisplayName: 'Local',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AnswerCard(answer: answer, questionText: 'test?'),
          ),
        ),
      );

      expect(find.byType(AnswerCard), findsOneWidget);
    });
  });
}
