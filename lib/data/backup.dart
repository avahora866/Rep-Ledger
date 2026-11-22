import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../models.dart';
import 'repository.dart';

const backupFormatVersion = 1;

enum ImportMode {
  /// Keep existing data; add new exercises and logs, skipping exact duplicates.
  merge,

  /// Wipe everything and load the file's contents.
  replace,
}

class ImportResult {
  const ImportResult({
    required this.typesAdded,
    required this.logsAdded,
    required this.logsSkipped,
  });
  final int typesAdded;
  final int logsAdded;
  final int logsSkipped;
}

/// Serialises everything to JSON. Logs reference exercises by name so the
/// file is human-readable and portable between installs.
Future<String> exportJson(LedgerRepository repo) async {
  final types = await repo.exerciseTypes();
  final namesById = {for (final t in types) t.id!: t.name};
  final logRows = await repo.db.query('logs', orderBy: 'performed_at, id');
  final logs = logRows.map(LogEntry.fromRow);

  final data = {
    'app': 'rep_ledger',
    'formatVersion': backupFormatVersion,
    'exportedAt': DateTime.now().toUtc().toIso8601String(),
    'exerciseTypes': [
      for (final t in types)
        {
          'name': t.name,
          'kind': t.kind.dbValue,
          'archived': t.archived,
          if (t.goal != null) 'goal': t.goal,
        },
    ],
    'logs': [
      for (final l in logs)
        {
          'exercise': namesById[l.exerciseTypeId],
          'performedAt': l.performedAt.toUtc().toIso8601String(),
          if (l.reps != null) 'reps': l.reps,
          if (l.weightKg != null) 'weightKg': l.weightKg,
          if (l.durationSeconds != null) 'durationSeconds': l.durationSeconds,
        },
    ],
  };
  return const JsonEncoder.withIndent('  ').convert(data);
}

class _ParsedLog {
  _ParsedLog(
    this.exercise,
    this.performedAt,
    this.reps,
    this.weightKg,
    this.durationSeconds,
  );
  final String exercise;
  final DateTime performedAt;
  final int? reps;
  final double? weightKg;
  final int? durationSeconds;
}

/// Validates the whole file before touching the database, then applies it in
/// a single transaction, so a bad file never leaves partial data behind.
Future<ImportResult> importJson(
  LedgerRepository repo,
  String json,
  ImportMode mode,
) async {
  final Object? decoded;
  try {
    decoded = jsonDecode(json);
  } on FormatException {
    throw const FormatException('File is not valid JSON');
  }
  if (decoded is! Map || decoded['app'] != 'rep_ledger') {
    throw const FormatException('Not a Rep Ledger export file');
  }
  final version = decoded['formatVersion'];
  if (version is! int || version > backupFormatVersion) {
    throw FormatException('Unsupported export format version: $version');
  }

  final fileTypes = <String, ExerciseType>{}; // lower-case name -> type
  for (final raw in (decoded['exerciseTypes'] as List? ?? const [])) {
    if (raw is! Map || raw['name'] is! String || raw['kind'] is! String) {
      throw const FormatException('Invalid exercise entry in file');
    }
    final name = (raw['name'] as String).trim();
    if (name.isEmpty) throw const FormatException('Exercise with empty name');
    fileTypes[name.toLowerCase()] = ExerciseType(
      name: name,
      kind: ExerciseKind.fromDb(raw['kind'] as String),
      archived: raw['archived'] == true,
      goal: switch (raw['goal']) {
        final num g when g > 0 => g.toInt(),
        _ => null,
      },
    );
  }

  final logs = <_ParsedLog>[];
  for (final raw in (decoded['logs'] as List? ?? const [])) {
    if (raw is! Map ||
        raw['exercise'] is! String ||
        raw['performedAt'] is! String) {
      throw const FormatException('Invalid log entry in file');
    }
    final exercise = (raw['exercise'] as String).trim();
    if (!fileTypes.containsKey(exercise.toLowerCase())) {
      throw FormatException('Log refers to unknown exercise "$exercise"');
    }
    final performedAt = DateTime.tryParse(raw['performedAt'] as String);
    if (performedAt == null) {
      throw FormatException('Invalid date "${raw['performedAt']}"');
    }
    logs.add(
      _ParsedLog(
        exercise,
        performedAt.toLocal(),
        (raw['reps'] as num?)?.toInt(),
        (raw['weightKg'] as num?)?.toDouble(),
        (raw['durationSeconds'] as num?)?.toInt(),
      ),
    );
  }

  var typesAdded = 0, logsAdded = 0, logsSkipped = 0;

  await repo.db.transaction((txn) async {
    if (mode == ImportMode.replace) {
      await txn.delete('logs');
      await txn.delete('exercise_types');
    }

    final idByName = <String, int>{};
    final existing = (await txn.query(
      'exercise_types',
    )).map(ExerciseType.fromRow);
    for (final t in existing) {
      idByName[t.name.toLowerCase()] = t.id!;
      final incoming = fileTypes[t.name.toLowerCase()];
      if (incoming != null && incoming.kind != t.kind) {
        throw FormatException(
          '"${t.name}" is "${t.kind.label}" here but '
          '"${incoming.kind.label}" in the file',
        );
      }
    }
    for (final entry in fileTypes.entries) {
      if (idByName.containsKey(entry.key)) continue;
      idByName[entry.key] = await txn.insert(
        'exercise_types',
        entry.value.toRow(),
      );
      typesAdded++;
    }

    for (final l in logs) {
      final typeId = idByName[l.exercise.toLowerCase()]!;
      final ms = l.performedAt.millisecondsSinceEpoch;
      if (mode == ImportMode.merge) {
        final dup = await txn.rawQuery(
          'SELECT 1 FROM logs WHERE exercise_type_id = ? AND performed_at = ? '
          'AND reps IS ? AND weight_kg IS ? AND duration_seconds IS ? LIMIT 1',
          [typeId, ms, l.reps, l.weightKg, l.durationSeconds],
        );
        if (dup.isNotEmpty) {
          logsSkipped++;
          continue;
        }
      }
      await txn.insert('logs', {
        'exercise_type_id': typeId,
        'performed_at': ms,
        'reps': l.reps,
        'weight_kg': l.weightKg,
        'duration_seconds': l.durationSeconds,
      }, conflictAlgorithm: ConflictAlgorithm.abort);
      logsAdded++;
    }
  });

  repo.notifyChanged();
  return ImportResult(
    typesAdded: typesAdded,
    logsAdded: logsAdded,
    logsSkipped: logsSkipped,
  );
}
