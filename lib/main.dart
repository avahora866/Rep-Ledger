import 'package:flutter/material.dart';

import 'data/repository.dart';
import 'ui/home_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final db = await openLedgerDatabase();
  runApp(RepLedgerApp(repo: LedgerRepository(db)));
}

class RepLedgerApp extends StatelessWidget {
  const RepLedgerApp({super.key, required this.repo});

  final LedgerRepository repo;

  @override
  Widget build(BuildContext context) {
    const seed = Colors.teal;
    return MaterialApp(
      title: 'Rep Ledger',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: seed)),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: seed,
          brightness: Brightness.dark,
        ),
      ),
      home: HomeScreen(repo: repo),
    );
  }
}
