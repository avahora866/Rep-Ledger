import '../models.dart';

/// Entries of the same exercise whose start falls within this window of the
/// group's first entry are collapsed together.
const groupWindow = Duration(minutes: 30);

class LogGroup {
  LogGroup(this.type, this.entries);

  final ExerciseType type;

  /// Ordered by time, never empty.
  final List<LogEntry> entries;

  DateTime get start => entries.first.performedAt;
  DateTime get end => entries.last.performedAt;
  bool get isSingle => entries.length == 1;

  int get totalReps => entries.fold(0, (s, e) => s + (e.reps ?? 0));

  int get totalSeconds =>
      entries.fold(0, (s, e) => s + (e.durationSeconds ?? 0));

  /// Sum of reps × weight, for weighted exercises.
  double get volumeKg =>
      entries.fold(0.0, (s, e) => s + (e.reps ?? 0) * (e.weightKg ?? 0));

  double? get minWeight =>
      _weights.isEmpty ? null : _weights.reduce((a, b) => a < b ? a : b);
  double? get maxWeight =>
      _weights.isEmpty ? null : _weights.reduce((a, b) => a > b ? a : b);
  Iterable<double> get _weights =>
      entries.map((e) => e.weightKg).whereType<double>();
}

/// Groups a day's logs: same exercise type, each group spanning at most
/// [window] from its first entry. Entries don't need to be adjacent, so
/// supersets (push ups, curls, push ups, curls…) still group per exercise.
/// Groups are returned in order of their first entry.
List<LogGroup> groupLogs(
  List<LogEntry> logs,
  Map<int, ExerciseType> typesById, {
  Duration window = groupWindow,
}) {
  final sorted = [...logs]
    ..sort((a, b) {
      final c = a.performedAt.compareTo(b.performedAt);
      return c != 0 ? c : (a.id ?? 0).compareTo(b.id ?? 0);
    });

  final groups = <LogGroup>[];
  final openGroupByType = <int, LogGroup>{};

  for (final log in sorted) {
    final type = typesById[log.exerciseTypeId];
    if (type == null) continue;
    final open = openGroupByType[log.exerciseTypeId];
    if (open != null && log.performedAt.difference(open.start) <= window) {
      open.entries.add(log);
    } else {
      final g = LogGroup(type, [log]);
      groups.add(g);
      openGroupByType[log.exerciseTypeId] = g;
    }
  }
  return groups;
}
