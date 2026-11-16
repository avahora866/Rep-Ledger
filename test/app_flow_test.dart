import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rep_ledger_v2/main.dart';

import 'helpers.dart';

/// Lets real (FFI) database futures complete between frames.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pumpAndSettle();
  }
}

void main() {
  testWidgets('log sets, see them grouped, expand, flip days, config', (
    tester,
  ) async {
    final repo = (await tester.runAsync(newTestRepo))!;
    await tester.pumpWidget(RepLedgerApp(repo: repo));
    await settle(tester);

    expect(find.text('Today'), findsOneWidget);
    expect(find.text('Nothing logged'), findsOneWidget);

    // First set: pick Push ups (defaults to 10 reps) and add.
    await tester.tap(find.text('Log'));
    await settle(tester);
    await tester.tap(find.widgetWithText(ChoiceChip, 'Push ups'));
    await settle(tester);
    expect(find.widgetWithText(TextField, '10'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextField, '10'), '12');
    await tester.tap(find.text('Add'));
    await settle(tester);

    expect(find.text('Push ups'), findsOneWidget);
    expect(find.textContaining('12 reps'), findsOneWidget);

    // Quick "log another set" repeats the last values and forms a group.
    await tester.tap(find.byTooltip('Log another set'));
    await settle(tester);
    expect(find.textContaining('24 reps · 2 sets'), findsOneWidget);
    expect(find.text('Set 1'), findsNothing); // collapsed

    await tester.tap(find.text('Push ups'));
    await settle(tester);
    expect(find.text('Set 1'), findsOneWidget);
    expect(find.text('Set 2'), findsOneWidget);

    // Flip to yesterday and back.
    await tester.tap(find.byTooltip('Previous day'));
    await settle(tester);
    expect(find.text('Yesterday'), findsOneWidget);
    expect(find.text('Nothing logged'), findsOneWidget);
    await tester.tap(find.byTooltip('Jump to today'));
    await settle(tester);
    expect(find.text('Today'), findsOneWidget);
    expect(find.textContaining('24 reps · 2 sets'), findsOneWidget);

    // Config: add a new exercise type.
    await tester.tap(find.byTooltip('Exercises & data'));
    await settle(tester);
    expect(find.text('Export'), findsOneWidget);
    expect(find.text('Import'), findsOneWidget);
    await tester.tap(find.text('Exercise'));
    await settle(tester);
    await tester.enterText(find.byType(TextField), 'Goblet squats');
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('Reps + weight'),
      ),
    );
    await tester.tap(find.text('Save'));
    await settle(tester);
    expect(find.text('Goblet squats'), findsOneWidget);
    final saved = (await tester.runAsync(
      repo.exerciseTypes,
    ))!.firstWhere((t) => t.name == 'Goblet squats');
    expect(saved.kind.name, 'weighted');

    await tester.runAsync(() => repo.db.close());
  });
}
