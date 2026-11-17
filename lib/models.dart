/// How an exercise is measured.
enum ExerciseKind {
  /// Bodyweight reps, e.g. "10 push ups".
  reps('reps', 'Reps'),

  /// Reps at a weight, e.g. "10 dumbbell curls at 10 kg".
  weighted('weighted', 'Reps + weight'),

  /// Held for a duration, e.g. "hamstring stretch for 30 seconds".
  timed('timed', 'Duration');

  const ExerciseKind(this.dbValue, this.label);

  final String dbValue;
  final String label;

  static ExerciseKind fromDb(String value) => ExerciseKind.values.firstWhere(
    (k) => k.dbValue == value,
    orElse: () => throw FormatException('Unknown exercise kind "$value"'),
  );
}

class ExerciseType {
  const ExerciseType({
    this.id,
    required this.name,
    required this.kind,
    this.archived = false,
  });

  final int? id;
  final String name;
  final ExerciseKind kind;

  /// Archived types keep their history but are hidden from the add-log picker.
  final bool archived;

  ExerciseType copyWith({String? name, ExerciseKind? kind, bool? archived}) =>
      ExerciseType(
        id: id,
        name: name ?? this.name,
        kind: kind ?? this.kind,
        archived: archived ?? this.archived,
      );

  factory ExerciseType.fromRow(Map<String, Object?> row) => ExerciseType(
    id: row['id'] as int,
    name: row['name'] as String,
    kind: ExerciseKind.fromDb(row['kind'] as String),
    archived: (row['archived'] as int) == 1,
  );

  Map<String, Object?> toRow() => {
    if (id != null) 'id': id,
    'name': name,
    'kind': kind.dbValue,
    'archived': archived ? 1 : 0,
  };

  @override
  bool operator ==(Object other) =>
      other is ExerciseType &&
      other.id == id &&
      other.name == name &&
      other.kind == kind &&
      other.archived == archived;

  @override
  int get hashCode => Object.hash(id, name, kind, archived);
}

class LogEntry {
  const LogEntry({
    this.id,
    required this.exerciseTypeId,
    required this.performedAt,
    this.reps,
    this.weightKg,
    this.durationSeconds,
  });

  final int? id;
  final int exerciseTypeId;
  final DateTime performedAt;
  final int? reps;
  final double? weightKg;
  final int? durationSeconds;

  LogEntry copyWith({
    int? exerciseTypeId,
    DateTime? performedAt,
    int? reps,
    double? weightKg,
    int? durationSeconds,
  }) => LogEntry(
    id: id,
    exerciseTypeId: exerciseTypeId ?? this.exerciseTypeId,
    performedAt: performedAt ?? this.performedAt,
    reps: reps ?? this.reps,
    weightKg: weightKg ?? this.weightKg,
    durationSeconds: durationSeconds ?? this.durationSeconds,
  );

  factory LogEntry.fromRow(Map<String, Object?> row) => LogEntry(
    id: row['id'] as int,
    exerciseTypeId: row['exercise_type_id'] as int,
    performedAt: DateTime.fromMillisecondsSinceEpoch(
      row['performed_at'] as int,
    ),
    reps: row['reps'] as int?,
    weightKg: (row['weight_kg'] as num?)?.toDouble(),
    durationSeconds: row['duration_seconds'] as int?,
  );

  Map<String, Object?> toRow() => {
    if (id != null) 'id': id,
    'exercise_type_id': exerciseTypeId,
    'performed_at': performedAt.millisecondsSinceEpoch,
    'reps': reps,
    'weight_kg': weightKg,
    'duration_seconds': durationSeconds,
  };
}
