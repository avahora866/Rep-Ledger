import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:rep_ledger_v2/data/backup.dart';
import 'package:rep_ledger_v2/data/repository.dart';
import 'package:rep_ledger_v2/models.dart';

import 'helpers.dart';

Future<ExerciseType> typeNamed(LedgerRepository r, String name) async =>
    (await r.exerciseTypes()).firstWhere((t) => t.name == name);

void main() {
  late LedgerRepository repo;
  setUp(() async => repo = await newTestRepo());
  tearDown(() => repo.db.close());

  Future<void> seedLogs(LedgerRepository r) async {
    final curls = await typeNamed(r, 'Dumbbell curls');
    final stretch = await typeNamed(r, 'Hamstring stretch');
    await r.saveLog(
      LogEntry(
        exerciseTypeId: curls.id!,
        performedAt: DateTime(2026, 11, 16, 9, 0, 12),
        reps: 10,
        weightKg: 12.5,
      ),
    );
    await r.saveLog(
      LogEntry(
        exerciseTypeId: stretch.id!,
        performedAt: DateTime(2026, 11, 16, 9, 5),
        durationSeconds: 30,
      ),
    );
    await r.saveExerciseType(
      const ExerciseType(
        name: 'Plank',
        kind: ExerciseKind.timed,
        archived: true,
      ),
    );
  }

  test('export then import into a fresh db round-trips', () async {
    await seedLogs(repo);
    final json = await exportJson(repo);

    final other = await newTestRepo();
    final result = await importJson(other, json, ImportMode.replace);
    expect(result.typesAdded, 4);
    expect(result.logsAdded, 2);

    expect(await exportJson(other), isNot(isEmpty));
    final logs = await other.logsForDay(DateTime(2026, 11, 16));
    expect(logs.length, 2);
    expect(logs.first.weightKg, 12.5);
    expect(logs.first.performedAt, DateTime(2026, 11, 16, 9, 0, 12));
    expect((await typeNamed(other, 'Plank')).archived, isTrue);
    await other.db.close();
  });

  test('merge skips exact duplicates', () async {
    await seedLogs(repo);
    final json = await exportJson(repo);
    final r = await importJson(repo, json, ImportMode.merge);
    expect(r.logsAdded, 0);
    expect(r.logsSkipped, 2);
    expect(r.typesAdded, 0);
  });

  test('replace wipes existing data', () async {
    await seedLogs(repo);
    final file = jsonEncode({
      'app': 'rep_ledger',
      'formatVersion': 1,
      'exerciseTypes': [
        {'name': 'Squats', 'kind': 'reps'},
      ],
      'logs': [
        {
          'exercise': 'Squats',
          'performedAt': '2026-11-16T10:00:00Z',
          'reps': 20,
        },
      ],
    });
    await importJson(repo, file, ImportMode.replace);
    expect((await repo.exerciseTypes()).map((t) => t.name), ['Squats']);
  });

  test('kind conflict on merge aborts without changes', () async {
    final file = jsonEncode({
      'app': 'rep_ledger',
      'formatVersion': 1,
      'exerciseTypes': [
        {'name': 'Push ups', 'kind': 'timed'},
        {'name': 'New one', 'kind': 'reps'},
      ],
      'logs': [],
    });
    await expectLater(
      importJson(repo, file, ImportMode.merge),
      throwsFormatException,
    );
    expect((await repo.exerciseTypes()).length, 3);
  });

  test('rejects invalid files', () async {
    for (final bad in [
      'not json',
      '{"app":"something-else"}',
      jsonEncode({
        'app': 'rep_ledger',
        'formatVersion': 1,
        'exerciseTypes': [],
        'logs': [
          {'exercise': 'Ghost', 'performedAt': '2026-11-16T10:00:00Z'},
        ],
      }),
    ]) {
      await expectLater(
        importJson(repo, bad, ImportMode.replace),
        throwsFormatException,
      );
    }
    expect((await repo.exerciseTypes()).length, 3);
  });
}
