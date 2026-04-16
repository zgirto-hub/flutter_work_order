import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:work_order/screens/manual_assistant/widgets/variants_modal.dart';

void main() {
  group('VariantsModal', () {
    testWidgets('shows all seeded chips', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: VariantsModal(
              originalQuestion: 'original question',
              generatedVariants: ['variant1', 'variant2', 'variant3'],
            ),
          ),
        ),
      );

      expect(find.byType(InputChip), findsNWidgets(4));
    });

    testWidgets('Save all returns non-empty trimmed texts',
        (WidgetTester tester) async {
      List<String>? result;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async {
                  result = await showVariantsModal(
                    context: context,
                    originalQuestion: 'a',
                    generatedVariants: ['  ', 'b'],
                  );
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Save all'));
      await tester.pumpAndSettle();

      expect(result, ['a', 'b']);
    });

    testWidgets('Cancel returns null', (WidgetTester tester) async {
      List<String>? result;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async {
                  result = await showVariantsModal(
                    context: context,
                    originalQuestion: 'original',
                    generatedVariants: [],
                  );
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(result, isNull);
    });

    testWidgets('Save all disabled when all chips empty',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: VariantsModal(
              originalQuestion: '',
              generatedVariants: ['   '],
            ),
          ),
        ),
      );

      final saveButton = find.widgetWithText(FilledButton, 'Save all');
      expect(saveButton, findsOneWidget);

      final button = tester.widget<FilledButton>(saveButton);
      expect(button.onPressed, isNull);
    });

    testWidgets('shows notice when provided', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: VariantsModal(
              originalQuestion: 'original',
              generatedVariants: [],
              notice: 'Automatic variants could not be generated.',
            ),
          ),
        ),
      );

      expect(find.text('Automatic variants could not be generated.'),
          findsOneWidget);
    });
  });
}
