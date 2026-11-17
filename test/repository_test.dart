import 'package:flutter_test/flutter_test.dart';
import 'package:rep_ledger_v2/data/repository.dart';
import 'package:rep_ledger_v2/models.dart';

import 'helpers.dart';

void main() {
  late LedgerRepository repo;
  setUp(() async => repo = await newTestRepo());
  tearDown(() => repo.db.close());

  test('seeds starter exercises', () async {
    final types = await repo.exerciseTypes();
    expect(types.map((t) => t.name), [
      'Dumbbell curls',
      'Hamstring stretch',
      'Push ups',
    ]);
  });

  test('rejects duplicate names case-insensitively', () async {
    expect(
      () => repo.saveExerciseType(
        const ExerciseType(name: ' push UPS ', kind: ExerciseKind.reps),
      ),
      throwsA(isA<DuplicateExerciseNameException>()),
    );
  });

  test('logsForDay returns only that day, in time order', () async {
    final t = (await repo.exerciseTypes()).first;
    for (final at in [
      DateTime(2026, 11, 16, 23, 59),
      DateTime(2026, 11, 16, 0, 0),
      DateTime(2026, 11, 17, 0, 0),
      DateTime(2026, 11, 15, 23, 59),
    ]) {
      await repo.saveLog(
        LogEntry(exerciseTypeId: t.id!, performedAt: at, reps: 1, weightKg: 5),
      );
    }
    final logs = await repo.logsForDay(DateTime(2026, 11, 16, 12));
    expect(logs.map((l) => l.performedAt.hour), [0, 23]);
  });

  test(
    'cannot delete a type that has logs; restoreLog undoes delete',
    () async {
      final t = (await repo.exerciseTypes()).first;
      final saved = await repo.saveLog(
        LogEntry(exerciseTypeId: t.id!, performedAt: DateTime.now(), reps: 3),
      );
      expect(() => repo.deleteExerciseType(t.id!), throwsStateError);

      await repo.deleteLog(saved.id!);
      expect(await repo.logCountForType(t.id!), 0);
      await repo.restoreLog(saved);
      final last = await repo.lastLogForType(t.id!);
      expect(last?.id, saved.id);
      expect(last?.reps, 3);
    },
  );

  test('notifies listeners on writes', () async {
    var calls = 0;
    repo.addListener(() => calls++);
    final t = (await repo.exerciseTypes()).first;
    await repo.saveLog(
      LogEntry(exerciseTypeId: t.id!, performedAt: DateTime.now(), reps: 1),
    );
    expect(calls, 1);
  });
}
