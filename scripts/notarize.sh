#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
APP_PATH="${1:-$REPO_ROOT/build/Screamer.app}"
ZIP_PATH="$REPO_ROOT/build/Screamer.zip"

if [[ -z "${APPLE_ID:-}" ]]; then
  echo "error: APPLE_ID is required for notarization." >&2
  exit 1
fi
if [[ -z "${TEAM_ID:-}" ]]; then
  echo "error: TEAM_ID is required for notarization." >&2
  exit 1
fi
if [[ -z "${APP_SPECIFIC_PASSWORD:-}" ]]; then
  echo "error: APP_SPECIFIC_PASSWORD is required for notarization." >&2
  exit 1
fi

if [[ ! -d "$APP_PATH" ]]; then
  echo "error: app bundle not found at $APP_PATH" >&2
  exit 1
fi

echo "[notarize] Creating zip archive at $ZIP_PATH"
rm -f "$ZIP_PATH"
ditto -c -k --keepParent "$APP_PATH" "$ZIP_PATH"

echo "[notarize] Submitting build to Apple notarization service..."
xcrun notarytool submit "$ZIP_PATH" \
  --apple-id "$APPLE_ID" \
  --team-id "$TEAM_ID" \
  --password "$APP_SPECIFIC_PASSWORD" \
  --wait

echo "[notarize] Stapling notarization ticket..."
xcrun stapler staple "$APP_PATH"

echo "[notarize] Notarization complete for $APP_PATH"
