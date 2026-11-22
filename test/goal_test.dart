import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:rep_ledger_v2/data/backup.dart';
import 'package:rep_ledger_v2/data/repository.dart';
import 'package:rep_ledger_v2/logic/grouping.dart';
import 'package:rep_ledger_v2/models.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'helpers.dart';

LogEntry _log(int type, {int? reps, int? secs, int minute = 0}) => LogEntry(
  id: minute + 1,
  exerciseTypeId: type,
  performedAt: DateTime(2026, 11, 16, 9, minute),
  reps: reps,
  durationSeconds: secs,
);

void main() {
  group('goal status', () {
    const pushUps = ExerciseType(
      id: 1,
      name: 'Push ups',
      kind: ExerciseKind.reps,
      goal: 50,
    );
    const curls = ExerciseType(
      id: 2,
      name: 'Curls',
      kind: ExerciseKind.weighted,
      goal: 20,
    );
    const plank = ExerciseType(
      id: 3,
      name: 'Plank',
      kind: ExerciseKind.timed,
      goal: 60,
    );
    const noGoal = ExerciseType(id: 4, name: 'Squats', kind: ExerciseKind.reps);
    final types = {1: pushUps, 2: curls, 3: plank, 4: noGoal};

    GoalStatus status(List<LogEntry> logs) =>
        groupLogs(logs, types).single.goalStatus;

    test('reps: below half, half, reached', () {
      expect(status([_log(1, reps: 24)]), GoalStatus.belowHalf);
      expect(status([_log(1, reps: 25)]), GoalStatus.halfway);
      expect(
        status([_log(1, reps: 30), _log(1, reps: 20, minute: 1)]),
        GoalStatus.reached,
      );
      expect(status([_log(1, reps: 80)]), GoalStatus.reached);
    });

    test('weighted counts reps', () {
      expect(status([_log(2, reps: 10)]), GoalStatus.halfway);
      expect(status([_log(2, reps: 20)]), GoalStatus.reached);
    });

    test('timed counts seconds', () {
      expect(status([_log(3, secs: 29)]), GoalStatus.belowHalf);
      expect(status([_log(3, secs: 30)]), GoalStatus.halfway);
      expect(status([_log(3, secs: 60)]), GoalStatus.reached);
    });

    test('no goal', () {
      expect(status([_log(4, reps: 1000)]), GoalStatus.none);
    });
  });

  test('goal is saved, updated and cleared', () async {
    final repo = await newTestRepo();
    final saved = await repo.saveExerciseType(
      const ExerciseType(name: 'Plank', kind: ExerciseKind.timed, goal: 60),
    );
    Future<ExerciseType> reload() async =>
        (await repo.exerciseTypes()).firstWhere((t) => t.id == saved.id);
    expect((await reload()).goal, 60);
    await repo.saveExerciseType(saved.copyWith(goal: 90));
    expect((await reload()).goal, 90);
    await repo.saveExerciseType(saved.copyWith(clearGoal: true));
    expect((await reload()).goal, isNull);
    await repo.db.close();
  });

  test('goals survive export / import', () async {
    final repo = await newTestRepo();
    final pushUps = (await repo.exerciseTypes()).firstWhere(
      (t) => t.name == 'Push ups',
    );
    await repo.saveExerciseType(pushUps.copyWith(goal: 50));
    final json = await exportJson(repo);

    final other = await newTestRepo();
    await importJson(other, json, ImportMode.replace);
    final types = await other.exerciseTypes();
    expect(types.firstWhere((t) => t.name == 'Push ups').goal, 50);
    expect(types.firstWhere((t) => t.name == 'Dumbbell curls').goal, isNull);
    await repo.db.close();
    await other.db.close();
  });

  test('upgrading a v1 database keeps all data and adds no goals', () async {
    sqfliteFfiInit();
    final factory = databaseFactoryFfiNoIsolate;
    final dir = await Directory.systemTemp.createTemp('rep_ledger_v1');
    final path = '${dir.path}/rep_ledger.db';

    // Exactly the original v1 schema.
    final v1 = await factory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, _) async {
          await db.execute('''
            CREATE TABLE exercise_types (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              name TEXT NOT NULL UNIQUE COLLATE NOCASE,
              kind TEXT NOT NULL CHECK (kind IN ('reps', 'weighted', 'timed')),
              archived INTEGER NOT NULL DEFAULT 0
            )
          ''');
          await db.execute('''
            CREATE TABLE logs (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              exercise_type_id INTEGER NOT NULL
                REFERENCES exercise_types(id) ON DELETE RESTRICT,
              performed_at INTEGER NOT NULL,
              reps INTEGER,
              weight_kg REAL,
              duration_seconds INTEGER
            )
          ''');
        },
      ),
    );
    final typeId = await v1.insert('exercise_types', {
      'name': 'Push ups',
      'kind': 'reps',
      'archived': 1,
    });
    final when = DateTime(2026, 11, 16, 9);
    await v1.insert('logs', {
      'exercise_type_id': typeId,
      'performed_at': when.millisecondsSinceEpoch,
      'reps': 12,
    });
    await v1.close();

    final repo = LedgerRepository(
      await openLedgerDatabase(factory: factory, path: path),
    );
    final types = await repo.exerciseTypes();
    expect(types, [
      ExerciseType(
        id: typeId,
        name: 'Push ups',
        kind: ExerciseKind.reps,
        archived: true,
      ),
    ]);
    final logs = await repo.logsForDay(when);
    expect(logs.single.reps, 12);
    expect(logs.single.performedAt, when);

    // And goals can be set on the upgraded database.
    await repo.saveExerciseType(types.single.copyWith(goal: 50));
    expect((await repo.exerciseTypes()).single.goal, 50);

    await repo.db.close();
    await dir.delete(recursive: true);
  });
}
