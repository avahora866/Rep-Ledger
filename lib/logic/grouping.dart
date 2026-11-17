import '../models.dart';

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

/// Groups a day's logs: one group per exercise type, holding every entry of
/// that exercise for the day. Groups are ordered by their first entry.
List<LogGroup> groupLogs(
  List<LogEntry> logs,
  Map<int, ExerciseType> typesById,
) {
  final sorted = [...logs]
    ..sort((a, b) {
      final c = a.performedAt.compareTo(b.performedAt);
      return c != 0 ? c : (a.id ?? 0).compareTo(b.id ?? 0);
    });

  // Map preserves insertion order, i.e. order of each type's first entry.
  final byType = <int, LogGroup>{};
  for (final log in sorted) {
    final type = typesById[log.exerciseTypeId];
    if (type == null) continue;
    byType.putIfAbsent(type.id!, () => LogGroup(type, [])).entries.add(log);
  }
  return byType.values.toList();
}
