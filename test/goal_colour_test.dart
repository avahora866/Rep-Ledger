import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rep_ledger_v2/main.dart';
import 'package:rep_ledger_v2/models.dart';

import 'app_flow_test.dart' show settle;
import 'helpers.dart';

void main() {
  testWidgets('day card turns blue at half the goal and green at the goal', (
    tester,
  ) async {
    final repo = (await tester.runAsync(newTestRepo))!;
    final pushUps = (await tester.runAsync(
      repo.exerciseTypes,
    ))!.firstWhere((t) => t.name == 'Push ups');
    await tester.runAsync(
      () => repo.saveExerciseType(pushUps.copyWith(goal: 20)),
    );
    Future<void> logReps(int reps) => tester.runAsync(
      () => repo.saveLog(
        LogEntry(
          exerciseTypeId: pushUps.id!,
          performedAt: DateTime.now(),
          reps: reps,
        ),
      ),
    );
    Color? cardColour() => tester
        .widget<Card>(
          find.ancestor(of: find.text('Push ups'), matching: find.byType(Card)),
        )
        .color;

    await tester.pumpWidget(RepLedgerApp(repo: repo));
    await logReps(5);
    await settle(tester);
    expect(cardColour(), isNull);

    await logReps(5);
    await settle(tester);
    expect(cardColour(), Colors.blue.shade100);

    await logReps(10);
    await settle(tester);
    expect(cardColour(), Colors.green.shade100);

    await tester.runAsync(() => repo.db.close());
  });
}
