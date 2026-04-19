import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:work_order/screens/manual_assistant/widgets/review_entry_card.dart';
import 'package:work_order/screens/manual_assistant/widgets/feedback_reason_sheet.dart';

void main() {
  group('ReviewEntryCard _buildReasonChip', () {
    final testEntry = {
      'id': 'test-id',
      'question_text': 'Test question?',
      'answer_text': 'Test answer.',
      'rating': 'negative',
      'rater_email': 'test@example.com',
      'feedback_reason': null,
      'feedback_comment': null,
    };

    testWidgets('Inaccurate chip has correct color 0xFFE57373', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (ctx) {
                final state = _TestReviewEntryCardState(entry: {
                  ...testEntry,
                  'feedback_reason': 'inaccurate',
                });
                return state.buildReasonChip();
              },
            ),
          ),
        ),
      );
      expect(find.text('Inaccurate'), findsOneWidget);
      final chip = tester.widget<Chip>(find.byType(Chip));
      expect(chip.backgroundColor, equals(const Color(0xFFE57373).withValues(alpha: 0.2)));
    });

    testWidgets('Incomplete chip has correct color 0xFFFFB74D', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (ctx) {
                final state = _TestReviewEntryCardState(entry: {
                  ...testEntry,
                  'feedback_reason': 'incomplete',
                });
                return state.buildReasonChip();
              },
            ),
          ),
        ),
      );
      expect(find.text('Incomplete'), findsOneWidget);
      final chip = tester.widget<Chip>(find.byType(Chip));
      expect(chip.backgroundColor, equals(const Color(0xFFFFB74D).withValues(alpha: 0.2)));
    });

    testWidgets('Outdated chip has correct color 0xFFFFCA28', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (ctx) {
                final state = _TestReviewEntryCardState(entry: {
                  ...testEntry,
                  'feedback_reason': 'outdated',
                });
                return state.buildReasonChip();
              },
            ),
          ),
        ),
      );
      expect(find.text('Outdated'), findsOneWidget);
      final chip = tester.widget<Chip>(find.byType(Chip));
      expect(chip.backgroundColor, equals(const Color(0xFFFFCA28).withValues(alpha: 0.2)));
    });

    testWidgets('Wrong source chip uses deepPurple.shade400 (0xFF7E57C2)', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (ctx) {
                final state = _TestReviewEntryCardState(entry: {
                  ...testEntry,
                  'feedback_reason': 'wrong_source',
                });
                return state.buildReasonChip();
              },
            ),
          ),
        ),
      );
      expect(find.text('Wrong source'), findsOneWidget);
      final chip = tester.widget<Chip>(find.byType(Chip));
      expect(chip.backgroundColor, equals(Colors.deepPurple.shade400.withValues(alpha: 0.2)));
    });

    testWidgets('Unclear chip has correct color 0xFF90A4AE', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (ctx) {
                final state = _TestReviewEntryCardState(entry: {
                  ...testEntry,
                  'feedback_reason': 'unclear',
                });
                return state.buildReasonChip();
              },
            ),
          ),
        ),
      );
      expect(find.text('Unclear'), findsOneWidget);
      final chip = tester.widget<Chip>(find.byType(Chip));
      expect(chip.backgroundColor, equals(const Color(0xFF90A4AE).withValues(alpha: 0.2)));
    });

    testWidgets('null reason shows No reason given chip with grey color', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (ctx) {
                final state = _TestReviewEntryCardState(entry: testEntry);
                return state.buildReasonChip();
              },
            ),
          ),
        ),
      );
      expect(find.text('No reason given'), findsOneWidget);
      final chip = tester.widget<Chip>(find.byType(Chip));
      expect(chip.backgroundColor, equals(Colors.grey.shade300));
    });
  });
}

class _TestReviewEntryCardState {
  final Map<String, dynamic> entry;

  _TestReviewEntryCardState({required this.entry});

  Widget buildReasonChip() {
    final reason = entry['feedback_reason'] as String?;
    final feedbackReason = FeedbackReason.fromValue(reason);
    if (feedbackReason == null) {
      return Chip(
        label: const Text('No reason given', style: TextStyle(fontSize: 11)),
        backgroundColor: Colors.grey.shade300,
        side: BorderSide.none,
        padding: EdgeInsets.zero,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      );
    }
    return Chip(
      label: Text(feedbackReason.label, style: const TextStyle(fontSize: 11)),
      backgroundColor: feedbackReason.color.withValues(alpha: 0.2),
      side: BorderSide(color: feedbackReason.color),
      padding: EdgeInsets.zero,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }
}
