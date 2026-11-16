import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/repository.dart';
import '../logic/format.dart';
import '../models.dart';
import 'config_screen.dart';

/// Opens the add (or edit, when [existing] is given) log sheet for [day].
Future<void> showLogSheet(
  BuildContext context, {
  required LedgerRepository repo,
  required DateTime day,
  LogEntry? existing,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    builder: (_) => _LogSheet(repo: repo, day: day, existing: existing),
  );
}

class _LogSheet extends StatefulWidget {
  const _LogSheet({required this.repo, required this.day, this.existing});

  final LedgerRepository repo;
  final DateTime day;
  final LogEntry? existing;

  @override
  State<_LogSheet> createState() => _LogSheetState();
}

class _LogSheetState extends State<_LogSheet> {
  final _reps = TextEditingController();
  final _weight = TextEditingController();
  final _minutes = TextEditingController();
  final _secs = TextEditingController();

  List<ExerciseType>? _types;
  ExerciseType? _selected;
  late TimeOfDay _time;
  String? _error;

  bool get _editing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _time = TimeOfDay.fromDateTime(e?.performedAt ?? DateTime.now());
    if (e != null) _fillFrom(e);
    _loadTypes();
  }

  @override
  void dispose() {
    _reps.dispose();
    _weight.dispose();
    _minutes.dispose();
    _secs.dispose();
    super.dispose();
  }

  Future<void> _loadTypes() async {
    final all = await widget.repo.exerciseTypes();
    final recent = await widget.repo.recentlyUsedTypeIds();
    final rank = {for (final (i, id) in recent.indexed) id: i};
    final visible =
        all
            .where(
              (t) => !t.archived || t.id == widget.existing?.exerciseTypeId,
            )
            .toList()
          // Most recently used first, then never-used alphabetically.
          ..sort((a, b) {
            final ra = rank[a.id] ?? 1 << 30, rb = rank[b.id] ?? 1 << 30;
            return ra != rb ? ra.compareTo(rb) : a.name.compareTo(b.name);
          });
    if (!mounted) return;
    setState(() {
      _types = visible;
      if (_editing) {
        _selected = visible.firstWhere(
          (t) => t.id == widget.existing!.exerciseTypeId,
        );
      }
    });
  }

  void _fillFrom(LogEntry e) {
    _reps.text = e.reps?.toString() ?? '';
    _weight.text = e.weightKg == null
        ? ''
        : formatWeight(e.weightKg!).replaceAll(' kg', '');
    _setDuration(e.durationSeconds);
  }

  void _setDuration(int? totalSeconds) {
    if (totalSeconds == null) {
      _minutes.text = '';
      _secs.text = '';
      return;
    }
    _minutes.text = (totalSeconds ~/ 60).toString();
    _secs.text = (totalSeconds % 60).toString().padLeft(2, '0');
  }

  /// Minutes + seconds as total seconds; null if both are blank/invalid.
  /// Seconds over 59 are allowed (e.g. 0:90 = 90s).
  int? _durationSeconds() {
    final m = int.tryParse(_minutes.text.trim());
    final s = int.tryParse(_secs.text.trim());
    if (m == null && s == null) return null;
    return (m ?? 0) * 60 + (s ?? 0);
  }

  Future<void> _select(ExerciseType t) async {
    setState(() {
      _selected = t;
      _error = null;
    });
    if (_editing) return;
    // Prefill with whatever was logged last time for this exercise.
    final last = await widget.repo.lastLogForType(t.id!);
    if (!mounted || _selected != t) return;
    setState(() {
      if (last != null) {
        _fillFrom(last);
      } else {
        _reps.text = t.kind == ExerciseKind.timed ? '' : '10';
        _weight.text = '';
        _setDuration(t.kind == ExerciseKind.timed ? 30 : null);
      }
    });
  }

  Future<void> _pickTime() async {
    final t = await showTimePicker(context: context, initialTime: _time);
    if (t != null) setState(() => _time = t);
  }

  Future<void> _save() async {
    final type = _selected;
    if (type == null) {
      setState(() => _error = 'Pick an exercise');
      return;
    }
    final reps = int.tryParse(_reps.text.trim());
    final weight = double.tryParse(_weight.text.trim().replaceAll(',', '.'));
    final seconds = _durationSeconds();

    String? error;
    switch (type.kind) {
      case ExerciseKind.reps:
        if (reps == null || reps <= 0) error = 'Enter a number of reps';
      case ExerciseKind.weighted:
        if (reps == null || reps <= 0) {
          error = 'Enter a number of reps';
        } else if (weight == null || weight < 0) {
          error = 'Enter a weight';
        }
      case ExerciseKind.timed:
        if (seconds == null || seconds <= 0) error = 'Enter a duration';
    }
    if (error != null) {
      setState(() => _error = error);
      return;
    }

    final d = widget.existing?.performedAt ?? widget.day;
    final keepSeconds =
        widget.existing != null &&
        TimeOfDay.fromDateTime(widget.existing!.performedAt) == _time;
    final now = DateTime.now();
    final performedAt = keepSeconds
        ? widget.existing!.performedAt
        : DateTime(
            d.year,
            d.month,
            d.day,
            _time.hour,
            _time.minute,
            // Seconds keep quick successive logs in the order entered.
            _editing ? 0 : now.second,
          );

    await widget.repo.saveLog(
      LogEntry(
        id: widget.existing?.id,
        exerciseTypeId: type.id!,
        performedAt: performedAt,
        reps: type.kind == ExerciseKind.timed ? null : reps,
        weightKg: type.kind == ExerciseKind.weighted ? weight : null,
        durationSeconds: type.kind == ExerciseKind.timed ? seconds : null,
      ),
    );
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _delete() async {
    await widget.repo.deleteLog(widget.existing!.id!);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final types = _types;
    final textTheme = Theme.of(context).textTheme;

    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        bottom: MediaQuery.viewInsetsOf(context).bottom + 16,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              _editing ? 'Edit log' : 'Log exercise',
              style: textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            if (types == null)
              const Center(child: CircularProgressIndicator())
            else if (types.isEmpty)
              _NoExercises(repo: widget.repo, onAdded: _loadTypes)
            else
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  for (final t in types)
                    ChoiceChip(
                      label: Text(t.name),
                      selected: _selected?.id == t.id,
                      onSelected: (_) => _select(t),
                    ),
                ],
              ),
            if (_selected != null) ...[
              const SizedBox(height: 16),
              ..._fieldsFor(_selected!.kind),
              const SizedBox(height: 8),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.schedule),
                title: Text(_time.format(context)),
                subtitle: const Text('Time'),
                trailing: const Icon(Icons.edit),
                onTap: _pickTime,
              ),
            ],
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            const SizedBox(height: 16),
            Row(
              children: [
                if (_editing)
                  TextButton.icon(
                    onPressed: _delete,
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Delete'),
                    style: TextButton.styleFrom(
                      foregroundColor: Theme.of(context).colorScheme.error,
                    ),
                  ),
                const Spacer(),
                FilledButton(
                  onPressed: _selected == null ? null : _save,
                  child: Text(_editing ? 'Save' : 'Add'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _fieldsFor(ExerciseKind kind) {
    switch (kind) {
      case ExerciseKind.reps:
        return [_StepperField(controller: _reps, label: 'Reps', step: 1)];
      case ExerciseKind.weighted:
        return [
          _StepperField(controller: _reps, label: 'Reps', step: 1),
          const SizedBox(height: 12),
          _StepperField(
            controller: _weight,
            label: 'Weight',
            suffix: 'kg',
            step: 2.5,
            decimal: true,
          ),
        ];
      case ExerciseKind.timed:
        return [
          _DurationField(
            minutes: _minutes,
            seconds: _secs,
            read: _durationSeconds,
            write: _setDuration,
          ),
        ];
    }
  }
}

/// A numeric text field with − / + buttons for one-tap adjustments.
class _StepperField extends StatelessWidget {
  const _StepperField({
    required this.controller,
    required this.label,
    required this.step,
    this.suffix,
    this.decimal = false,
  });

  final TextEditingController controller;
  final String label;
  final String? suffix;
  final num step;
  final bool decimal;

  void _bump(int direction) {
    final current =
        num.tryParse(controller.text.trim().replaceAll(',', '.')) ?? 0;
    var next = current + step * direction;
    if (next < 0) next = 0;
    controller.text = decimal
        ? formatWeight(next.toDouble()).replaceAll(' kg', '')
        : next.round().toString();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        IconButton.filledTonal(
          tooltip: 'Decrease $label',
          onPressed: () => _bump(-1),
          icon: const Icon(Icons.remove),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: TextField(
            controller: controller,
            textAlign: TextAlign.center,
            keyboardType: TextInputType.numberWithOptions(decimal: decimal),
            inputFormatters: [
              FilteringTextInputFormatter.allow(
                decimal ? RegExp(r'[0-9.,]') : RegExp(r'[0-9]'),
              ),
            ],
            decoration: InputDecoration(
              labelText: label,
              suffixText: suffix,
              border: const OutlineInputBorder(),
            ),
          ),
        ),
        const SizedBox(width: 8),
        IconButton.filledTonal(
          tooltip: 'Increase $label',
          onPressed: () => _bump(1),
          icon: const Icon(Icons.add),
        ),
      ],
    );
  }
}

/// Minutes : seconds entry with − / + buttons that step by 5 seconds.
class _DurationField extends StatelessWidget {
  const _DurationField({
    required this.minutes,
    required this.seconds,
    required this.read,
    required this.write,
  });

  final TextEditingController minutes;
  final TextEditingController seconds;
  final int? Function() read;
  final void Function(int) write;

  static const _step = 5;

  void _bump(int direction) {
    final next = (read() ?? 0) + _step * direction;
    write(next < 0 ? 0 : next);
  }

  Widget _box(TextEditingController c, String label) => Expanded(
    child: TextField(
      controller: c,
      textAlign: TextAlign.center,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      onTap: () => c.selection = TextSelection(
        baseOffset: 0,
        extentOffset: c.text.length,
      ),
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        IconButton.filledTonal(
          tooltip: 'Decrease duration',
          onPressed: () => _bump(-1),
          icon: const Icon(Icons.remove),
        ),
        const SizedBox(width: 8),
        _box(minutes, 'Min'),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 6),
          child: Text(':', style: TextStyle(fontSize: 20)),
        ),
        _box(seconds, 'Sec'),
        const SizedBox(width: 8),
        IconButton.filledTonal(
          tooltip: 'Increase duration',
          onPressed: () => _bump(1),
          icon: const Icon(Icons.add),
        ),
      ],
    );
  }
}

class _NoExercises extends StatelessWidget {
  const _NoExercises({required this.repo, required this.onAdded});

  final LedgerRepository repo;
  final VoidCallback onAdded;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const Text('No exercises set up yet.'),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          icon: const Icon(Icons.add),
          label: const Text('Add an exercise'),
          onPressed: () async {
            await showExerciseTypeDialog(context, repo: repo);
            onAdded();
          },
        ),
      ],
    );
  }
}
