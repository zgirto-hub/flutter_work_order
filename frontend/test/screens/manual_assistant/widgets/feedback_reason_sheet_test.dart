import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:work_order/screens/manual_assistant/widgets/feedback_reason_sheet.dart';

void main() {
  group('FeedbackReasonSheet', () {
    testWidgets('(a) tapping Skip returns null', (tester) async {
      FeedbackSheetResult? result;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (ctx) => ElevatedButton(
                onPressed: () async {
                  result = await FeedbackReasonSheet.show(ctx);
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Skip'));
      await tester.pumpAndSettle();

      expect(result, isNull);
    });

    testWidgets('(b) swipe-to-dismiss returns null', (tester) async {
      FeedbackSheetResult? result;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (ctx) => ElevatedButton(
                onPressed: () async {
                  result = await FeedbackReasonSheet.show(ctx);
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.drag(find.byType(FeedbackReasonSheet), const Offset(0, 200));
      await tester.pumpAndSettle();

      expect(result, isNull);
    });

    testWidgets('(c) Save button is disabled until a reason chip is selected', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (ctx) => ElevatedButton(
                onPressed: () => FeedbackReasonSheet.show(ctx),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      final saveButton = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Save'),
      );
      expect(saveButton.onPressed, isNull);
    });

    testWidgets('(d) selecting chip + tapping Save returns FeedbackSheetResult with correct reason and comment', (tester) async {
      FeedbackSheetResult? result;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (ctx) => ElevatedButton(
                onPressed: () async {
                  result = await FeedbackReasonSheet.show(ctx);
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Outdated'));
      await tester.pumpAndSettle();

      final commentField = find.byType(TextField);
      await tester.enterText(commentField, 'This is outdated.');
      await tester.pumpAndSettle();

      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(result, isNotNull);
      expect(result!.reason, equals('outdated'));
      expect(result!.comment, equals('This is outdated.'));
    });
  });
}
