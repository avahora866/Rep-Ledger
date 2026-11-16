import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../data/backup.dart';
import '../data/repository.dart';
import '../models.dart';

class ConfigScreen extends StatefulWidget {
  const ConfigScreen({super.key, required this.repo});

  final LedgerRepository repo;

  @override
  State<ConfigScreen> createState() => _ConfigScreenState();
}

class _ConfigScreenState extends State<ConfigScreen> {
  List<ExerciseType>? _types;

  LedgerRepository get repo => widget.repo;

  @override
  void initState() {
    super.initState();
    repo.addListener(_load);
    _load();
  }

  @override
  void dispose() {
    repo.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    final types = await repo.exerciseTypes();
    if (mounted) setState(() => _types = types);
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _delete(ExerciseType t) async {
    final count = await repo.logCountForType(t.id!);
    if (!mounted) return;
    if (count > 0) {
      _toast('${t.name} has $count logs. Archive it instead to keep history.');
      return;
    }
    await repo.deleteExerciseType(t.id!);
  }

  Future<void> _export() async {
    try {
      final json = await exportJson(repo);
      final name =
          'rep-ledger-${DateFormat('yyyy-MM-dd').format(DateTime.now())}.json';
      final uri = await FilePicker.saveFile(
        dialogTitle: 'Export Rep Ledger data',
        fileName: name,
        bytes: utf8.encode(json),
        mimeType: 'application/json',
      );
      if (uri != null) _toast('Exported to $name');
    } catch (e) {
      _toast('Export failed: $e');
    }
  }

  Future<void> _import() async {
    final String contents;
    try {
      final file = await FilePicker.pickFile(
        dialogTitle: 'Import Rep Ledger data',
      );
      if (file == null) return;
      contents = utf8.decode(await file.readAsBytes());
    } catch (e) {
      _toast('Could not read file: $e');
      return;
    }
    if (!mounted) return;

    final mode = await showDialog<ImportMode>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Import data'),
        content: const Text(
          'Merge adds the file\'s exercises and logs to what you have '
          '(exact duplicates are skipped).\n\n'
          'Replace deletes everything currently in the app first.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, ImportMode.replace),
            child: const Text('Replace'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, ImportMode.merge),
            child: const Text('Merge'),
          ),
        ],
      ),
    );
    if (mode == null || !mounted) return;

    if (mode == ImportMode.replace) {
      final sure = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Replace all data?'),
          content: const Text(
            'All current exercises and logs will be deleted. '
            'Consider exporting a backup first.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Replace'),
            ),
          ],
        ),
      );
      if (sure != true) return;
    }

    try {
      final r = await importJson(repo, contents, mode);
      _toast(
        'Imported ${r.logsAdded} logs, ${r.typesAdded} new exercises'
        '${r.logsSkipped > 0 ? ' (${r.logsSkipped} duplicates skipped)' : ''}',
      );
    } on FormatException catch (e) {
      _toast('Import failed: ${e.message}');
    } catch (e) {
      _toast('Import failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final types = _types;
    final active = types?.where((t) => !t.archived).toList() ?? const [];
    final archived = types?.where((t) => t.archived).toList() ?? const [];
    final headerStyle = Theme.of(context).textTheme.titleSmall?.copyWith(
      color: Theme.of(context).colorScheme.primary,
    );

    Widget header(String text) => Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
      child: Text(text, style: headerStyle),
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Exercises & data')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showExerciseTypeDialog(context, repo: repo),
        icon: const Icon(Icons.add),
        label: const Text('Exercise'),
      ),
      body: types == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.only(bottom: 96),
              children: [
                header('Exercises'),
                if (active.isEmpty)
                  const ListTile(title: Text('No exercises yet')),
                for (final t in active) _typeTile(t),
                if (archived.isNotEmpty) ...[
                  header('Archived'),
                  for (final t in archived) _typeTile(t),
                ],
                header('Data'),
                ListTile(
                  leading: const Icon(Icons.upload_file),
                  title: const Text('Export'),
                  subtitle: const Text('Save all exercises and logs as JSON'),
                  onTap: _export,
                ),
                ListTile(
                  leading: const Icon(Icons.download),
                  title: const Text('Import'),
                  subtitle: const Text('Load a Rep Ledger JSON export'),
                  onTap: _import,
                ),
              ],
            ),
    );
  }

  Widget _typeTile(ExerciseType t) {
    return ListTile(
      title: Text(
        t.name,
        style: t.archived
            ? TextStyle(color: Theme.of(context).disabledColor)
            : null,
      ),
      subtitle: Text(t.kind.label),
      onTap: () => showExerciseTypeDialog(context, repo: repo, existing: t),
      trailing: PopupMenuButton<String>(
        onSelected: (action) {
          switch (action) {
            case 'archive':
              repo.saveExerciseType(t.copyWith(archived: !t.archived));
            case 'delete':
              _delete(t);
          }
        },
        itemBuilder: (_) => [
          PopupMenuItem(
            value: 'archive',
            child: Text(t.archived ? 'Unarchive' : 'Archive'),
          ),
          const PopupMenuItem(value: 'delete', child: Text('Delete')),
        ],
      ),
    );
  }
}

/// Add or edit an exercise type. The measurement kind is locked once the
/// exercise has logs, since changing it would make old logs meaningless.
Future<void> showExerciseTypeDialog(
  BuildContext context, {
  required LedgerRepository repo,
  ExerciseType? existing,
}) async {
  final hasLogs =
      existing != null && await repo.logCountForType(existing.id!) > 0;
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (_) => _ExerciseTypeDialog(
      repo: repo,
      existing: existing,
      kindLocked: hasLogs,
    ),
  );
}

class _ExerciseTypeDialog extends StatefulWidget {
  const _ExerciseTypeDialog({
    required this.repo,
    required this.existing,
    required this.kindLocked,
  });

  final LedgerRepository repo;
  final ExerciseType? existing;
  final bool kindLocked;

  @override
  State<_ExerciseTypeDialog> createState() => _ExerciseTypeDialogState();
}

class _ExerciseTypeDialogState extends State<_ExerciseTypeDialog> {
  late final _name = TextEditingController(text: widget.existing?.name);
  late ExerciseKind _kind = widget.existing?.kind ?? ExerciseKind.reps;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Enter a name');
      return;
    }
    try {
      await widget.repo.saveExerciseType(
        widget.existing?.copyWith(name: name, kind: _kind) ??
            ExerciseType(name: name, kind: _kind),
      );
      if (mounted) Navigator.of(context).pop();
    } on DuplicateExerciseNameException catch (e) {
      setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.existing == null ? 'New exercise' : 'Edit exercise'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _name,
            autofocus: widget.existing == null,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              labelText: 'Name',
              hintText: 'e.g. Push ups',
              errorText: _error,
            ),
            onSubmitted: (_) => _save(),
          ),
          const SizedBox(height: 16),
          Text('Measured by', style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 4),
          RadioGroup<ExerciseKind>(
            groupValue: _kind,
            onChanged: (k) {
              if (!widget.kindLocked && k != null) setState(() => _kind = k);
            },
            child: Column(
              children: [
                for (final k in ExerciseKind.values)
                  RadioListTile<ExerciseKind>(
                    value: k,
                    enabled: !widget.kindLocked,
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: Text(k.label),
                    subtitle: Text(switch (k) {
                      ExerciseKind.reps => 'e.g. 10 push ups',
                      ExerciseKind.weighted => 'e.g. 10 curls at 10 kg',
                      ExerciseKind.timed => 'e.g. stretch for 30 seconds',
                    }),
                  ),
              ],
            ),
          ),
          if (widget.kindLocked)
            Text(
              'Can\'t change how it\'s measured once it has logs.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }
}
