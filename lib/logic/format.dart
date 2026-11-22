import '../models.dart';
import 'grouping.dart';

String formatWeight(double kg) {
  final s = kg == kg.roundToDouble()
      ? kg.toStringAsFixed(0)
      : kg.toStringAsFixed(2).replaceFirst(RegExp(r'0+$'), '');
  return '$s kg';
}

String formatDuration(int totalSeconds) {
  final h = totalSeconds ~/ 3600;
  final m = (totalSeconds % 3600) ~/ 60;
  final s = totalSeconds % 60;
  if (h > 0) return '${h}h ${m}m${s > 0 ? ' ${s}s' : ''}';
  if (m > 0) return '${m}m${s > 0 ? ' ${s}s' : ''}';
  return '${s}s';
}

String formatTime(DateTime t) =>
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

/// One entry, e.g. "10 reps", "10 × 12.5 kg", "30s".
String describeEntry(ExerciseKind kind, LogEntry e) {
  switch (kind) {
    case ExerciseKind.reps:
      return '${e.reps ?? 0} reps';
    case ExerciseKind.weighted:
      return '${e.reps ?? 0} × ${formatWeight(e.weightKg ?? 0)}';
    case ExerciseKind.timed:
      return formatDuration(e.durationSeconds ?? 0);
  }
}

/// Group total, e.g. "30 reps · 3 sets" or "30 reps @ 10–12.5 kg · 325 kg vol".
String describeGroupTotal(LogGroup g) {
  final sets = '${g.entries.length} sets';
  switch (g.type.kind) {
    case ExerciseKind.reps:
      return '${g.totalReps} reps · $sets';
    case ExerciseKind.weighted:
      final lo = g.minWeight ?? 0, hi = g.maxWeight ?? 0;
      final weight = lo == hi
          ? formatWeight(lo)
          : '${formatWeight(lo).replaceAll(' kg', '')}–${formatWeight(hi)}';
      return '${g.totalReps} reps @ $weight · $sets · '
          '${formatWeight(g.volumeKg)} vol';
    case ExerciseKind.timed:
      return '${formatDuration(g.totalSeconds)} · $sets';
  }
}

/// A goal in its exercise's unit, e.g. "50 reps" or "1m".
String describeGoal(ExerciseKind kind, int goal) =>
    kind == ExerciseKind.timed ? formatDuration(goal) : '$goal reps';
