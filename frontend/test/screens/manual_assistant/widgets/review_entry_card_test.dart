import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:work_order/screens/manual_assistant/widgets/review_entry_card.dart';

// These tests exercise the real ReviewEntryCard widget (not a local copy of its
// internal chip-building helper). They assert on the Chip that appears in the
// rendered tree for each of the five reason categories plus the null case.

Widget _wrap(Map<String, dynamic> entry) {
  return MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(
        child: ReviewEntryCard(
          entry: entry,
          onApprove: (_) {},
          onCorrect: (_, __) {},
          onDelete: (_) {},
        ),
      ),
    ),
  );
}

Map<String, dynamic> _entry({String? reason, String? comment}) => {
      'id': 'test-id',
      'question_text': 'Test question?',
      'answer_text': 'Test answer.',
      'rating': 'negative',
      'rater_email': 'test@example.com',
      'created_at': '2026-04-19T06:00:00Z',
      'source_chunks': <dynamic>[],
      'feedback_reason': reason,
      'feedback_comment': comment,
    };

// Finds the reason Chip by locating whichever Chip descendant has the
// expected label text. Keeps tests resilient if future versions add more
// Chip-typed widgets to the card.
Chip _findChipByLabel(WidgetTester tester, String label) {
  final chip = tester.widgetList<Chip>(find.byType(Chip)).firstWhere(
        (c) => c.label is Text && (c.label as Text).data == label,
        orElse: () => throw StateError('No Chip with label "$label" found'),
      );
  return chip;
}

void main() {
  group('ReviewEntryCard reason chip', () {
    testWidgets('Inaccurate → red shade400 with alpha', (tester) async {
      await tester.pumpWidget(_wrap(_entry(reason: 'inaccurate')));
      expect(find.text('Inaccurate'), findsOneWidget);
      final chip = _findChipByLabel(tester, 'Inaccurate');
      expect(chip.backgroundColor,
          const Color(0xFFE57373).withValues(alpha: 0.2));
    });

    testWidgets('Incomplete → orange shade400 with alpha', (tester) async {
      await tester.pumpWidget(_wrap(_entry(reason: 'incomplete')));
      expect(find.text('Incomplete'), findsOneWidget);
      final chip = _findChipByLabel(tester, 'Incomplete');
      expect(chip.backgroundColor,
          const Color(0xFFFFB74D).withValues(alpha: 0.2));
    });

    testWidgets('Outdated → amber shade600 with alpha', (tester) async {
      await tester.pumpWidget(_wrap(_entry(reason: 'outdated')));
      expect(find.text('Outdated'), findsOneWidget);
      final chip = _findChipByLabel(tester, 'Outdated');
      expect(chip.backgroundColor,
          const Color(0xFFFFCA28).withValues(alpha: 0.2));
    });

    testWidgets('Wrong source → deepPurple shade400 with alpha', (tester) async {
      await tester.pumpWidget(_wrap(_entry(reason: 'wrong_source')));
      expect(find.text('Wrong source'), findsOneWidget);
      final chip = _findChipByLabel(tester, 'Wrong source');
      expect(
        chip.backgroundColor,
        Colors.deepPurple.shade400.withValues(alpha: 0.2),
      );
    });

    testWidgets('Unclear → blueGrey shade400 with alpha', (tester) async {
      await tester.pumpWidget(_wrap(_entry(reason: 'unclear')));
      expect(find.text('Unclear'), findsOneWidget);
      final chip = _findChipByLabel(tester, 'Unclear');
      expect(chip.backgroundColor,
          const Color(0xFF90A4AE).withValues(alpha: 0.2));
    });

    testWidgets('null reason → "No reason given" muted grey chip',
        (tester) async {
      await tester.pumpWidget(_wrap(_entry()));
      expect(find.text('No reason given'), findsOneWidget);
      final chip = _findChipByLabel(tester, 'No reason given');
      expect(chip.backgroundColor, Colors.grey.shade300);
    });
  });

  group('ReviewEntryCard comment preview', () {
    testWidgets('short comment renders verbatim', (tester) async {
      await tester.pumpWidget(_wrap(_entry(
        reason: 'outdated',
        comment: 'Revision is from 2022.',
      )));
      expect(find.text('Revision is from 2022.'), findsOneWidget);
    });

    testWidgets('comment over 100 chars is truncated with ellipsis',
        (tester) async {
      final longComment = 'a' * 150;
      await tester.pumpWidget(_wrap(_entry(
        reason: 'inaccurate',
        comment: longComment,
      )));
      // The card renders `${comment.substring(0, 100)}…` — an ellipsis char.
      expect(find.text('${'a' * 100}…'), findsOneWidget);
      // The full text is NOT present in the collapsed preview.
      expect(find.text(longComment), findsNothing);
    });

    testWidgets('no comment → no preview widget rendered', (tester) async {
      await tester.pumpWidget(_wrap(_entry(reason: 'unclear')));
      // No italic preview text should appear. The chip's label is checked
      // elsewhere; here we just ensure the preview helper rendered nothing.
      final textWidgets = tester.widgetList<Text>(find.byType(Text)).toList();
      final hasItalicPreview = textWidgets.any(
        (t) => t.style?.fontStyle == FontStyle.italic,
      );
      expect(hasItalicPreview, isFalse);
    });
  });
}
