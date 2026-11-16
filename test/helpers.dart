import 'package:rep_ledger_v2/data/repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Fresh in-memory database per call (seeded with the starter exercises).
Future<LedgerRepository> newTestRepo() async {
  sqfliteFfiInit();
  final db = await openLedgerDatabase(
    factory: databaseFactoryFfiNoIsolate,
    path: inMemoryDatabasePath,
  );
  return LedgerRepository(db);
}
