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

Requires Flutter 3.24+ / Dart 3.5+ on the stable channel, and an SDK built for
your CPU — on Apple Silicon use the `arm64` build, not the Intel one.

```bash
cd frontend
flutter pub get
./scripts/run_dev.sh          # flutter run with the dev defines already set
flutter test                  # unit and widget tests
```

Start the backend first; the app talks to it over the base URL below.

### Checks run before every commit

```bash
cd frontend
dart format .
flutter analyze
flutter test
```

CI runs the same three against every pull request, with
`dart format --output=none --set-exit-if-changed .`

## Environments

The app never hardcodes a base URL. `lib/core/network/api_config.dart` is the only
file that reads the compile-time environment, and no screen may read it directly:

```dart
class ApiConfig {
  static const baseUrl = String.fromEnvironment('API_BASE_URL',
      defaultValue: 'http://10.0.2.2:3000');
  static const env = String.fromEnvironment('APP_ENV', defaultValue: 'dev');
}
```

| Define | Default | Purpose |
| --- | --- | --- |
| `API_BASE_URL` | `http://10.0.2.2:3000` | Root of the bank API, no trailing slash |
| `APP_ENV` | `dev` | `dev`, `staging` or `prod`; drives logging and banners |

Both are baked in at compile time, so they must be passed on every `run`, `build`
and `test` invocation that needs a non-default value.

**dev** — against the local mock API:

```bash
./scripts/run_dev.sh
# equivalent to:
flutter run \
  --dart-define=API_BASE_URL=http://10.0.2.2:3000 \
  --dart-define=APP_ENV=dev
```

**staging**:

```bash
flutter build apk \
  --dart-define=API_BASE_URL=https://staging.spendwise.invalid \
  --dart-define=APP_ENV=staging
```

**prod**:

```bash
flutter build apk --release \
  --dart-define=API_BASE_URL=https://api.spendwise.invalid \
  --dart-define=APP_ENV=prod
```

Notes:

- `10.0.2.2` is the Android emulator's alias for the host machine's `localhost`.
  On an iOS simulator or desktop use `http://localhost:3000`; on a physical device
  use the host's LAN address. `scripts/run_dev.sh` honours an `API_BASE_URL`
  environment variable so you can override it without editing the script.
- Tests that exercise the network use a hand-written fake Dio adapter and never
  open a socket, so `flutter test` works with the defaults.
- Once the list of defines grows, group them into
  `--dart-define-from-file=env/staging.json` instead of repeating flags.

## Architecture

<!-- Layer diagram, data flow, and the rules each layer enforces. Diagram lives in docs/. -->

## Profiling evidence

<!-- DevTools timeline captures, jank traces, and before/after measurements. -->

## Known limitations

<!-- Deliberate cuts, unhandled edge cases, and what production would need. -->

## Retrospective

<!-- What went well, what was rebuilt, and what would be done differently. -->
