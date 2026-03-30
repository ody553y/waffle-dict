#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
GENERATE_APPCAST="${GENERATE_APPCAST:-0}"

if [[ -z "${SPARKLE_PRIVATE_KEY_PATH:-}" ]]; then
  echo "error: SPARKLE_PRIVATE_KEY_PATH is required." >&2
  exit 1
fi

if [[ ! -f "$SPARKLE_PRIVATE_KEY_PATH" ]]; then
  echo "error: Sparkle private key not found at $SPARKLE_PRIVATE_KEY_PATH" >&2
  exit 1
fi

if [[ -z "${VERSION:-}" ]]; then
  echo "error: VERSION is required to locate build/Waffle-\${VERSION}.dmg." >&2
  exit 1
fi

DMG_PATH="${DMG_PATH_OVERRIDE:-$REPO_ROOT/build/Waffle-${VERSION}.dmg}"
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
SIGN_OUTPUT="$("$SPARKLE_SIGN_UPDATE_BIN" "$DMG_PATH" --ed-key-file "$SPARKLE_PRIVATE_KEY_PATH")"
echo "$SIGN_OUTPUT"

ED_SIGNATURE=""
if [[ "$SIGN_OUTPUT" =~ edSignature=\"?([^\"[:space:]]+)\"? ]]; then
  ED_SIGNATURE="${BASH_REMATCH[1]}"
fi

if [[ -z "$ED_SIGNATURE" ]]; then
  echo "error: could not parse edSignature from sign_update output." >&2
  exit 1
fi

ARCHIVE_LENGTH="$(stat -f "%z" "$DMG_PATH")"
echo "[sparkle] Parsed metadata: edSignature=<redacted>, length=$ARCHIVE_LENGTH"

if [[ "$GENERATE_APPCAST" == "1" || -n "${APPCAST_OUTPUT_PATH:-}" ]]; then
  APPCAST_VERSION="${APPCAST_VERSION:-$VERSION}"
  APPCAST_SHORT_VERSION="${APPCAST_SHORT_VERSION:-$VERSION}"
  APPCAST_DMG_URL="${APPCAST_DMG_URL:-https://updates.waffle.app/releases/Waffle-${VERSION}.dmg}"
  APPCAST_MINIMUM_SYSTEM_VERSION="${APPCAST_MINIMUM_SYSTEM_VERSION:-$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$REPO_ROOT/Sources/WaffleApp/Info.plist" 2>/dev/null || echo "14.0")}"

  if [[ -z "${APPCAST_PUB_DATE:-}" ]]; then
    if [[ -n "${SOURCE_DATE_EPOCH:-}" ]]; then
      APPCAST_PUB_DATE="$(LC_ALL=C date -u -r "$SOURCE_DATE_EPOCH" '+%a, %d %b %Y %H:%M:%S +0000')"
    else
      APPCAST_PUB_DATE="$(LC_ALL=C date -u '+%a, %d %b %Y %H:%M:%S +0000')"
      echo "warning: APPCAST_PUB_DATE not set; using current UTC time." >&2
    fi
  fi

  APPCAST_ED_SIGNATURE="$ED_SIGNATURE" \
  APPCAST_ARCHIVE_LENGTH="$ARCHIVE_LENGTH" \
  APPCAST_VERSION="$APPCAST_VERSION" \
  APPCAST_SHORT_VERSION="$APPCAST_SHORT_VERSION" \
  APPCAST_DMG_URL="$APPCAST_DMG_URL" \
  APPCAST_MINIMUM_SYSTEM_VERSION="$APPCAST_MINIMUM_SYSTEM_VERSION" \
  APPCAST_PUB_DATE="$APPCAST_PUB_DATE" \
  "$SCRIPT_DIR/generate-appcast.sh"
fi
