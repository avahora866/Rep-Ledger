# Rep Ledger

A Flutter app for logging exercises, stored locally in SQLite.

## Features

- **Quick logging** — tap **Log**, pick an exercise (most recently used first), and
  the form is prefilled with what you did last time. Three kinds of exercise:
  - **Reps** — e.g. 10 push ups
  - **Reps + weight** — e.g. 10 dumbbell curls at 10 kg
  - **Duration** — e.g. hamstring stretch for 30 seconds
- **One-tap repeat** — the ⊕ on any entry or group logs another set with the same values.
- **Day navigation** — swipe left/right, use the arrows, or tap the date to pick one.
- **Grouping** — logs of the same exercise within 30 minutes of the group's first
  entry collapse into one section showing totals (reps, weight range, volume,
  or total time). Expand to see each set.
- **Edit / delete** — tap an entry to edit it; long-press to delete (with undo).
- **Config screen** (⚙) — add, rename, archive or delete exercise types.
  Archived exercises keep their history but are hidden from the log picker.
  An exercise's measurement kind is locked once it has logs.
- **Import / export** — JSON file containing all exercises and logs. Import can
  *merge* (skips exact duplicates) or *replace* everything.

## Code layout

| Path | Purpose |
| --- | --- |
| `lib/models.dart` | `ExerciseType`, `LogEntry`, `ExerciseKind` |
| `lib/data/repository.dart` | SQLite schema + all reads/writes |
| `lib/data/backup.dart` | JSON import/export |
| `lib/logic/grouping.dart` | 30-minute grouping + totals |
| `lib/logic/format.dart` | Display strings |
| `lib/ui/` | Screens: day view, log sheet, config |

## Development

```bash
flutter pub get
flutter test
flutter run
```

Tests use `sqflite_common_ffi` with an in-memory database, so they run on the
host without a device.
