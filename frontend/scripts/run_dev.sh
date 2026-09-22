#!/usr/bin/env bash
#
# Launches SpendWise against a locally running mock API.
#
#   ./scripts/run_dev.sh                 # default device
#   ./scripts/run_dev.sh -d chrome       # extra args are passed to flutter run
#   API_BASE_URL=http://192.168.1.7:3000 ./scripts/run_dev.sh   # physical device
#
# 10.0.2.2 is the Android emulator's alias for the host's localhost. On an iOS
# simulator or desktop, override API_BASE_URL with http://localhost:3000.
set -euo pipefail

FRONTEND_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$FRONTEND_DIR"

API_BASE_URL="${API_BASE_URL:-http://10.0.2.2:3000}"
APP_ENV="${APP_ENV:-dev}"

echo "SpendWise [$APP_ENV] -> $API_BASE_URL"

exec flutter run \
  --dart-define=API_BASE_URL="$API_BASE_URL" \
  --dart-define=APP_ENV="$APP_ENV" \
  "$@"
