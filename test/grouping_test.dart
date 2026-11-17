import 'package:flutter_test/flutter_test.dart';
import 'package:rep_ledger_v2/logic/format.dart';
import 'package:rep_ledger_v2/logic/grouping.dart';
import 'package:rep_ledger_v2/models.dart';

const pushUps = ExerciseType(id: 1, name: 'Push ups', kind: ExerciseKind.reps);
const curls = ExerciseType(id: 2, name: 'Curls', kind: ExerciseKind.weighted);
const stretch = ExerciseType(id: 3, name: 'Stretch', kind: ExerciseKind.timed);
final types = {1: pushUps, 2: curls, 3: stretch};

var _id = 0;
LogEntry log(int type, int h, int m, {int? reps, double? kg, int? secs}) =>
    LogEntry(
      id: ++_id,
      exerciseTypeId: type,
      performedAt: DateTime(2026, 11, 16, h, m),
      reps: reps,
      weightKg: kg,
      durationSeconds: secs,
    );

void main() {
  test('all entries of the same exercise on a day form one group', () {
    final groups = groupLogs([
      log(1, 7, 0, reps: 10),
      log(1, 9, 10, reps: 10),
      log(1, 21, 45, reps: 8), // hours apart: still the same group
    ], types);
    expect(groups.single.entries.length, 3);
    expect(groups.single.totalReps, 28);
  });

  test('groups are ordered by each exercise\'s first entry', () {
    final groups = groupLogs([
      log(2, 8, 0, reps: 5, kg: 10),
      log(1, 9, 0, reps: 10),
      log(2, 20, 0, reps: 5, kg: 10),
      log(3, 7, 0, secs: 30),
    ], types);
    expect(groups.map((g) => g.type.name), ['Stretch', 'Curls', 'Push ups']);
    expect(groups.map((g) => g.entries.length), [1, 2, 1]);
  });

  test('interleaved exercises (supersets) group per exercise', () {
    final groups = groupLogs([
      log(1, 9, 0, reps: 10),
      log(2, 9, 2, reps: 10, kg: 10),
      log(1, 9, 4, reps: 10),
      log(2, 9, 6, reps: 8, kg: 12.5),
    ], types);
    expect(groups.map((g) => g.type.name), ['Push ups', 'Curls']);
    expect(groups.map((g) => g.entries.length), [2, 2]);
  });

  test('input order does not matter', () {
    final groups = groupLogs([
      log(1, 9, 20, reps: 1),
      log(1, 9, 0, reps: 2),
    ], types);
    expect(groups.single.entries.map((e) => e.reps), [2, 1]);
  });

  test('group totals are described per kind', () {
    final w = groupLogs([
      log(2, 9, 0, reps: 10, kg: 10),
      log(2, 9, 5, reps: 10, kg: 12.5),
    ], types).single;
    expect(describeGroupTotal(w), '20 reps @ 10–12.5 kg · 2 sets · 225 kg vol');

    final t = groupLogs([
      log(3, 9, 0, secs: 30),
      log(3, 9, 1, secs: 45),
    ], types).single;
    expect(describeGroupTotal(t), '1m 15s · 2 sets');

    final r = groupLogs([
      log(1, 9, 0, reps: 10),
      log(1, 9, 1, reps: 12),
    ], types).single;
    expect(describeGroupTotal(r), '22 reps · 2 sets');
  });

  test('entry descriptions', () {
    expect(describeEntry(ExerciseKind.reps, log(1, 9, 0, reps: 10)), '10 reps');
    expect(
      describeEntry(ExerciseKind.weighted, log(2, 9, 0, reps: 10, kg: 10)),
      '10 × 10 kg',
    );
    expect(describeEntry(ExerciseKind.timed, log(3, 9, 0, secs: 30)), '30s');
  });
}
