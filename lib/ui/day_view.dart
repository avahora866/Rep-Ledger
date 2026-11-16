import 'package:flutter/material.dart';

import '../data/repository.dart';
import '../logic/format.dart';
import '../logic/grouping.dart';
import '../models.dart';
import 'log_sheet.dart';

/// One day's logs, grouped and collapsible.
class DayView extends StatefulWidget {
  const DayView({super.key, required this.repo, required this.day});

  final LedgerRepository repo;
  final DateTime day;

  @override
  State<DayView> createState() => _DayViewState();
}

class _DayViewState extends State<DayView> {
  List<LogGroup>? _groups;

  @override
  void initState() {
    super.initState();
    widget.repo.addListener(_load);
    _load();
  }

  @override
  void dispose() {
    widget.repo.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    final types = await widget.repo.exerciseTypes();
    final logs = await widget.repo.logsForDay(widget.day);
    if (!mounted) return;
    setState(() {
      _groups = groupLogs(logs, {for (final t in types) t.id!: t});
    });
  }

  @override
  Widget build(BuildContext context) {
    final groups = _groups;
    if (groups == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (groups.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.fitness_center,
              size: 48,
              color: Theme.of(context).colorScheme.outline,
            ),
            const SizedBox(height: 12),
            Text(
              'Nothing logged',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            const Text('Tap Log to add an exercise'),
          ],
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.only(top: 8, bottom: 96),
      itemCount: groups.length,
      itemBuilder: (context, i) => _GroupCard(
        // Keep expansion state stable as entries are added to the group.
        key: PageStorageKey('group-${groups[i].entries.first.id}'),
        group: groups[i],
        repo: widget.repo,
        day: widget.day,
      ),
    );
  }
}

class _GroupCard extends StatelessWidget {
  const _GroupCard({
    super.key,
    required this.group,
    required this.repo,
    required this.day,
  });

  final LogGroup group;
  final LedgerRepository repo;
  final DateTime day;

  Future<void> _logAnotherSet(BuildContext context) async {
    final last = group.entries.last;
    final now = DateTime.now();
    final isToday =
        now.year == day.year && now.month == day.month && now.day == day.day;
    // On past days, add just after the last set so it stays in this group.
    final at = isToday ? now : last.performedAt.add(const Duration(minutes: 1));
    final saved = await repo.saveLog(
      LogEntry(
        exerciseTypeId: last.exerciseTypeId,
        performedAt: at,
        reps: last.reps,
        weightKg: last.weightKg,
        durationSeconds: last.durationSeconds,
      ),
    );
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            'Logged ${group.type.name}: ${describeEntry(group.type.kind, saved)}',
          ),
          action: SnackBarAction(
            label: 'Undo',
            onPressed: () => repo.deleteLog(saved.id!),
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final type = group.type;
    final addButton = IconButton(
      tooltip: 'Log another set',
      icon: const Icon(Icons.add_circle_outline),
      onPressed: () => _logAnotherSet(context),
    );

    if (group.isSingle) {
      final e = group.entries.single;
      return Card(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        clipBehavior: Clip.antiAlias,
        child: ListTile(
          title: Text(type.name),
          subtitle: Text(
            '${describeEntry(type.kind, e)} · ${formatTime(e.performedAt)}',
          ),
          trailing: addButton,
          onTap: () => showLogSheet(context, repo: repo, day: day, existing: e),
          onLongPress: () => deleteWithUndo(context, repo, e, type),
        ),
      );
    }

    final range = '${formatTime(group.start)}–${formatTime(group.end)}';
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        key: PageStorageKey('tile-${group.entries.first.id}'),
        shape: const Border(),
        collapsedShape: const Border(),
        title: Text(type.name),
        subtitle: Text('${describeGroupTotal(group)}\n$range'),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [addButton, const Icon(Icons.expand_more)],
        ),
        children: [
          for (final (i, e) in group.entries.indexed)
            ListTile(
              dense: true,
              contentPadding: const EdgeInsets.only(left: 32, right: 16),
              leading: Text(
                'Set ${i + 1}',
                style: Theme.of(context).textTheme.labelMedium,
              ),
              title: Text(describeEntry(type.kind, e)),
              trailing: Text(formatTime(e.performedAt)),
              onTap: () =>
                  showLogSheet(context, repo: repo, day: day, existing: e),
              onLongPress: () => deleteWithUndo(context, repo, e, type),
            ),
        ],
      ),
    );
  }
}

/// Deletes [entry] and offers an undo that restores it exactly.
void deleteWithUndo(
  BuildContext context,
  LedgerRepository repo,
  LogEntry entry,
  ExerciseType type,
) {
  final messenger = ScaffoldMessenger.of(context);
  repo.deleteLog(entry.id!);
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(
          'Deleted ${type.name}: ${describeEntry(type.kind, entry)}',
        ),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () => repo.restoreLog(entry),
        ),
      ),
    );
}
