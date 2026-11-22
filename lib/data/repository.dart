import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

import '../models.dart';

const _schemaVersion = 2;

Future<void> _createSchema(Database db, int version) async {
  await db.execute('''
    CREATE TABLE exercise_types (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL UNIQUE COLLATE NOCASE,
      kind TEXT NOT NULL CHECK (kind IN ('reps', 'weighted', 'timed')),
      archived INTEGER NOT NULL DEFAULT 0,
      goal INTEGER
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
  await db.execute('CREATE INDEX idx_logs_performed_at ON logs(performed_at)');
  await db.execute(
    'CREATE INDEX idx_logs_type ON logs(exercise_type_id, performed_at)',
  );

  // Starter exercises so the app is usable straight away.
  for (final t in const [
    ExerciseType(name: 'Push ups', kind: ExerciseKind.reps),
    ExerciseType(name: 'Dumbbell curls', kind: ExerciseKind.weighted),
    ExerciseType(name: 'Hamstring stretch', kind: ExerciseKind.timed),
  ]) {
    await db.insert('exercise_types', t.toRow());
  }
}

/// Upgrades existing installs in place. Each step only adds; no data is
/// rewritten or dropped.
Future<void> _upgradeSchema(Database db, int oldVersion, int newVersion) async {
  if (oldVersion < 2) {
    // v2: optional daily goal per exercise. Existing exercises get no goal.
    await db.execute('ALTER TABLE exercise_types ADD COLUMN goal INTEGER');
  }
}

/// Opens the SQLite database. Pass [factory] / [path] to use an alternative
/// (e.g. in-memory FFI database in tests).
Future<Database> openLedgerDatabase({
  DatabaseFactory? factory,
  String? path,
}) async {
  final f = factory ?? databaseFactory;
  final dbPath = path ?? '${await f.getDatabasesPath()}/rep_ledger.db';
  return f.openDatabase(
    dbPath,
    options: OpenDatabaseOptions(
      version: _schemaVersion,
      onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
      onCreate: _createSchema,
      onUpgrade: _upgradeSchema,
    ),
  );
}

class DuplicateExerciseNameException implements Exception {
  DuplicateExerciseNameException(this.name);
  final String name;
  @override
  String toString() => 'An exercise called "$name" already exists';
}

/// All persistence goes through here. Notifies listeners on every write so
/// screens can refresh.
class LedgerRepository extends ChangeNotifier {
  LedgerRepository(this.db);

  final Database db;

  // ---- Exercise types ----

  Future<List<ExerciseType>> exerciseTypes({
    bool includeArchived = true,
  }) async {
    final rows = await db.query(
      'exercise_types',
      where: includeArchived ? null : 'archived = 0',
      orderBy: 'name COLLATE NOCASE',
    );
    return rows.map(ExerciseType.fromRow).toList();
  }

  Future<ExerciseType> saveExerciseType(ExerciseType type) async {
    final name = type.name.trim();
    final existing = await db.query(
      'exercise_types',
      columns: ['id'],
      where: 'name = ? COLLATE NOCASE',
      whereArgs: [name],
    );
    if (existing.isNotEmpty && existing.first['id'] != type.id) {
      throw DuplicateExerciseNameException(name);
    }
    final cleaned = type.copyWith(name: name);
    late final ExerciseType saved;
    if (type.id == null) {
      final id = await db.insert('exercise_types', cleaned.toRow());
      saved = ExerciseType(
        id: id,
        name: cleaned.name,
        kind: cleaned.kind,
        archived: cleaned.archived,
        goal: cleaned.goal,
      );
    } else {
      await db.update(
        'exercise_types',
        cleaned.toRow(),
        where: 'id = ?',
        whereArgs: [type.id],
      );
      saved = cleaned;
    }
    notifyListeners();
    return saved;
  }

  Future<int> logCountForType(int typeId) async {
    final r = await db.rawQuery(
      'SELECT COUNT(*) AS c FROM logs WHERE exercise_type_id = ?',
      [typeId],
    );
    return r.first['c'] as int;
  }

  /// Only types with no logs can be deleted; others should be archived.
  Future<void> deleteExerciseType(int typeId) async {
    if (await logCountForType(typeId) > 0) {
      throw StateError('Exercise has logs; archive it instead');
    }
    await db.delete('exercise_types', where: 'id = ?', whereArgs: [typeId]);
    notifyListeners();
  }

  // ---- Logs ----

  Future<List<LogEntry>> logsForDay(DateTime day) async {
    final start = DateTime(day.year, day.month, day.day);
    final end = DateTime(day.year, day.month, day.day + 1);
    final rows = await db.query(
      'logs',
      where: 'performed_at >= ? AND performed_at < ?',
      whereArgs: [start.millisecondsSinceEpoch, end.millisecondsSinceEpoch],
      orderBy: 'performed_at, id',
    );
    return rows.map(LogEntry.fromRow).toList();
  }

  /// The most recent log for a type, used to prefill the add form.
  Future<LogEntry?> lastLogForType(int typeId) async {
    final rows = await db.query(
      'logs',
      where: 'exercise_type_id = ?',
      whereArgs: [typeId],
      orderBy: 'performed_at DESC, id DESC',
      limit: 1,
    );
    return rows.isEmpty ? null : LogEntry.fromRow(rows.first);
  }

  /// Type ids ordered by most recently logged, for the quick-pick list.
  Future<List<int>> recentlyUsedTypeIds() async {
    final rows = await db.rawQuery(
      'SELECT exercise_type_id, MAX(performed_at) AS last '
      'FROM logs GROUP BY exercise_type_id ORDER BY last DESC',
    );
    return rows.map((r) => r['exercise_type_id'] as int).toList();
  }

  Future<LogEntry> saveLog(LogEntry log) async {
    late final LogEntry saved;
    if (log.id == null) {
      final id = await db.insert('logs', log.toRow());
      saved = LogEntry(
        id: id,
        exerciseTypeId: log.exerciseTypeId,
        performedAt: log.performedAt,
        reps: log.reps,
        weightKg: log.weightKg,
        durationSeconds: log.durationSeconds,
      );
    } else {
      await db.update(
        'logs',
        log.toRow(),
        where: 'id = ?',
        whereArgs: [log.id],
      );
      saved = log;
    }
    notifyListeners();
    return saved;
  }

  /// Re-inserts a deleted log with its original id (used by undo).
  Future<void> restoreLog(LogEntry log) async {
    await db.insert(
      'logs',
      log.toRow(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    notifyListeners();
  }

  Future<void> deleteLog(int id) async {
    await db.delete('logs', where: 'id = ?', whereArgs: [id]);
    notifyListeners();
  }

  /// Lets bulk operations (import) signal a refresh once at the end.
  void notifyChanged() => notifyListeners();
}
