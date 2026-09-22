# SpendWise

SpendWise is a personal spend-tracking app for a retail banking customer: it pulls a
month of card and UPI transactions from a bank API, cleans up messy merchant strings,
groups spend by category and merchant, and shows where the money actually went. The
user can recategorise a transaction (optionally applying that choice to every future
transaction from the same merchant, with an undo), set a monthly budget per category,
and read generated insights such as "dining is 38% above your three-month average".
The app is a Flutter client backed by a Node/Express mock API that serves realistic,
deterministic data — no database, everything in memory — so the whole system runs
offline on one machine. All money is handled as signed integer paise end to end.

## Folder layout

```
.
├── backend/               Node 20 + Express mock API (in-memory, no database)
├── frontend/              Flutter app
│   └── lib/
│       ├── app/           app shell, router, routes, theme
│       ├── core/          errors, network, security, motion, utils, cache, shared widgets
│       └── features/      one folder per feature: domain · data · state · presentation · widgets
├── docs/                  architecture diagram, profiling evidence, supporting notes
└── .github/workflows/     CI (backend job + frontend job)
```

Tests mirror the app structure under `frontend/test/{unit,widget,helpers}` and
`frontend/integration_test/`.

## Getting started

### Backend

```bash
cd backend
# TODO(P01): npm install
# TODO(P01): npm run dev       # starts the mock API on http://localhost:3000
# TODO(P01): npm test
```

### Frontend

```bash
cd frontend
# TODO(P02): flutter pub get
# TODO(P02): flutter run --dart-define=API_BASE_URL=http://localhost:3000
# TODO(P02): flutter test
```

### Checks run before every commit

```bash
cd frontend
# TODO(P02): dart format .
# TODO(P02): flutter analyze
```

## Environments

The app never hardcodes a base URL. `core/network/api_config.dart` reads it from the
compile-time environment:

```dart
const String.fromEnvironment('API_BASE_URL')
```

Supply it with `--dart-define` on every `run`, `build` and `test` invocation:

| Environment | Command |
| --- | --- |
| Local (desktop / iOS simulator) | `flutter run --dart-define=API_BASE_URL=http://localhost:3000` |
| Local (Android emulator) | `flutter run --dart-define=API_BASE_URL=http://10.0.2.2:3000` |
| Local (physical device on same LAN) | `flutter run --dart-define=API_BASE_URL=http://<your-lan-ip>:3000` |
| Staging build | `flutter build apk --dart-define=API_BASE_URL=https://staging.example.invalid` |

Notes:

- `10.0.2.2` is the Android emulator's alias for the host machine's `localhost`.
- Tests that exercise the network use a hand-written fake Dio adapter and do not need
  a real base URL, but the define must still be parseable.
- Multiple defines can be grouped in a `--dart-define-from-file=env/local.json` file
  if the list grows.

## Architecture

<!-- Layer diagram, data flow, and the rules each layer enforces. Diagram lives in docs/. -->

## Profiling evidence

<!-- DevTools timeline captures, jank traces, and before/after measurements. -->

## Known limitations

<!-- Deliberate cuts, unhandled edge cases, and what production would need. -->

## Retrospective

<!-- What went well, what was rebuilt, and what would be done differently. -->
