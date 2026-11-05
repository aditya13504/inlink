#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="$ROOT_DIR/app"

if ! command -v flutter >/dev/null 2>&1; then
  echo "ERROR: Flutter SDK is not installed or not on PATH." >&2
  echo "Install Flutter stable, then rerun this script." >&2
  exit 127
fi

cd "$APP_DIR"
echo "== Flutter toolchain =="
flutter --version
flutter doctor -v

echo "== Dependencies =="
flutter pub get

echo "== Formatting =="
dart format --output=none --set-exit-if-changed lib test

echo "== Static analysis =="
flutter analyze

echo "== Tests =="
flutter test --reporter expanded

echo "== Android debug build =="
flutter build apk --debug

echo "SUCCESS: Flutter checks and Android debug build completed."
echo "APK: $APP_DIR/build/app/outputs/flutter-apk/app-debug.apk"
