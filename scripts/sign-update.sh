#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

if [[ -z "${SPARKLE_PRIVATE_KEY_PATH:-}" ]]; then
  echo "error: SPARKLE_PRIVATE_KEY_PATH is required." >&2
  exit 1
fi

if [[ -z "${VERSION:-}" ]]; then
  echo "error: VERSION is required to locate build/Waffle-\${VERSION}.dmg." >&2
  exit 1
fi

DMG_PATH="$REPO_ROOT/build/Waffle-${VERSION}.dmg"
if [[ ! -f "$DMG_PATH" ]]; then
  echo "error: release archive not found at $DMG_PATH" >&2
  exit 1
fi

SPARKLE_SIGN_UPDATE_BIN="${SPARKLE_SIGN_UPDATE_BIN:-$REPO_ROOT/Sparkle/bin/sign_update}"
if [[ ! -x "$SPARKLE_SIGN_UPDATE_BIN" ]]; then
  echo "error: Sparkle sign_update tool not found at $SPARKLE_SIGN_UPDATE_BIN" >&2
  echo "hint: Set SPARKLE_SIGN_UPDATE_BIN to your Sparkle install's sign_update binary." >&2
  exit 1
fi

echo "[sparkle] Signing $DMG_PATH"
"$SPARKLE_SIGN_UPDATE_BIN" "$DMG_PATH" --ed-key-file "$SPARKLE_PRIVATE_KEY_PATH"
