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
npm install
npm run dev       # http://localhost:3000, restarts on save (node --watch)
npm start         # same server, no watcher
npm test          # node:test + supertest, no server needs to be running
PORT=4000 npm start
```

Sign in with **any** syntactically valid email and the password `password123`.
Every other route needs `Authorization: Bearer <token>`.

The dataset is generated from a seeded PRNG (seed `20260922`), so every boot
produces the same 8,700 transactions across six months ending with the current
one: ~900 this month, ~1,100 last month, 5,200 two months back (the stress
month), ~800, then an empty month, then ~700. About 3% are refunds — positive
`amountPaise` against the same category. Nothing is persisted; restarting the
server discards recategorisations, budgets and tokens.

Two contract details worth knowing before wiring the client:

- Every `POST`, `PUT` and `PATCH` requires an `Idempotency-Key` header
  (`400 IDEMPOTENCY_KEY_REQUIRED` without one). Replaying a key with the same
  body returns the stored response plus `Idempotency-Replayed: true`; replaying
  it with a different body is `409 IDEMPOTENCY_CONFLICT`. `POST /auth/login`
  accepts a key but does not demand one.
- `minPaise` / `maxPaise` filter on the **magnitude** of `amountPaise`, so one
  range matches both a ₹450 spend and a ₹450 refund. `month`, `from` and `to`
  are evaluated in UTC, which is also what the wire format uses.

#### Chaos endpoint

`/__chaos` makes the API misbehave on demand, so the client's loading, error and
retry states can be exercised without editing code. It needs no token and never
breaks itself or `/auth/login`.

```bash
curl -s localhost:3000/__chaos                                     # read current mode
curl -s -X POST localhost:3000/__chaos -H 'content-type: application/json' \
  -d '{"mode":"slow","latencyMs":2500}'                            # every response crawls
curl -s -X POST localhost:3000/__chaos -H 'content-type: application/json' \
  -d '{"mode":"error","failRate":0.5}'                             # half the calls 503
curl -s -X POST localhost:3000/__chaos -H 'content-type: application/json' \
  -d '{"mode":"offline"}'                                          # connection dropped
curl -s -X POST localhost:3000/__chaos -H 'content-type: application/json' \
  -d '{"mode":"off","latencyMs":0,"failRate":0}'                   # back to normal
```

`mode` is one of `off`, `slow`, `error`, `offline`; `latencyMs` is 0–30000 and
`failRate` is 0–1.

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
