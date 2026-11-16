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
  test('same type within 30 minutes of the first entry is grouped', () {
    final groups = groupLogs([
      log(1, 9, 0, reps: 10),
      log(1, 9, 10, reps: 10),
      log(1, 9, 30, reps: 8), // exactly 30 min: included
      log(1, 9, 31, reps: 5), // starts a new group
    ], types);
    expect(groups.map((g) => g.entries.length), [3, 1]);
    expect(groups.first.totalReps, 28);
  });

  test('window is anchored to the first entry, not chained', () {
    // Sets every 20 minutes must not chain into one all-day group.
    final groups = groupLogs([
      log(1, 9, 0, reps: 10),
      log(1, 9, 20, reps: 10),
      log(1, 9, 40, reps: 10),
      log(1, 10, 0, reps: 10),
    ], types);
    expect(groups.map((g) => g.entries.length), [2, 2]);
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
