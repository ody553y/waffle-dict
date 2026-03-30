#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
APP_NAME="Screamer"
APP_DIR="$REPO_ROOT/build/${APP_NAME}.app"
ENTITLEMENTS="$REPO_ROOT/Sources/ScreamerApp/ScreamerApp.entitlements"
INFO_PLIST_SOURCE="$REPO_ROOT/Sources/ScreamerApp/Info.plist"

if [[ -z "${SIGNING_IDENTITY:-}" ]]; then
  echo "error: SIGNING_IDENTITY is required (Developer ID Application certificate)." >&2
  exit 1
fi

if [[ ! -f "$ENTITLEMENTS" ]]; then
  echo "error: missing entitlements file at $ENTITLEMENTS" >&2
  exit 1
fi

if [[ ! -f "$INFO_PLIST_SOURCE" ]]; then
  echo "error: missing Info.plist at $INFO_PLIST_SOURCE" >&2
  exit 1
fi

cd "$REPO_ROOT"

echo "[release] Building ScreamerApp in release mode..."
swift build -c release --product ScreamerApp --disable-sandbox
BIN_DIR="$(swift build -c release --show-bin-path)"
BINARY="$BIN_DIR/ScreamerApp"

if [[ ! -x "$BINARY" ]]; then
  echo "error: expected built binary at $BINARY" >&2
  exit 1
fi

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources" "$APP_DIR/Contents/Frameworks"

echo "[release] Assembling app bundle at $APP_DIR"
cp "$BINARY" "$APP_DIR/Contents/MacOS/ScreamerApp"
cp "$INFO_PLIST_SOURCE" "$APP_DIR/Contents/Info.plist"

if [[ -d "$REPO_ROOT/worker" ]]; then
  cp -R "$REPO_ROOT/worker" "$APP_DIR/Contents/Resources/worker"
fi

CORE_BUNDLE="$(find "$BIN_DIR" -maxdepth 1 -type d -name '*_ScreamerCore.bundle' -print -quit || true)"
if [[ -n "$CORE_BUNDLE" ]]; then
  cp -R "$CORE_BUNDLE" "$APP_DIR/Contents/Resources/"
else
  echo "warning: ScreamerCore resource bundle not found in $BIN_DIR" >&2
fi

while IFS= read -r framework_path; do
  cp -R "$framework_path" "$APP_DIR/Contents/Frameworks/"
done < <(find "$BIN_DIR" -maxdepth 1 -type d -name '*.framework' | sort)

APP_BINARY="$APP_DIR/Contents/MacOS/ScreamerApp"
if ! otool -l "$APP_BINARY" | grep -q "@executable_path/../Frameworks"; then
  install_name_tool -add_rpath "@executable_path/../Frameworks" "$APP_BINARY" || true
fi

while IFS= read -r nested_binary; do
  codesign --force --timestamp --options runtime --sign "$SIGNING_IDENTITY" "$nested_binary"
done < <(find "$APP_DIR/Contents/Frameworks" -maxdepth 1 \
  \( -name '*.framework' -o -name '*.dylib' -o -name '*.app' \) | sort)

while IFS= read -r resource_bundle; do
  codesign --force --timestamp --sign "$SIGNING_IDENTITY" "$resource_bundle"
done < <(find "$APP_DIR/Contents/Resources" -maxdepth 1 -name '*.bundle' | sort)

echo "[release] Signing app with hardened runtime and entitlements..."
codesign \
  --force \
  --timestamp \
  --options runtime \
  --sign "$SIGNING_IDENTITY" \
  --entitlements "$ENTITLEMENTS" \
  "$APP_DIR"

codesign --verify --deep --strict "$APP_DIR"

VERSION="${VERSION:-$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_DIR/Contents/Info.plist")}"
DMG_PATH="$REPO_ROOT/build/${APP_NAME}-${VERSION}.dmg"
rm -f "$DMG_PATH"

if [[ "${NOTARIZE:-0}" == "1" ]]; then
  "$SCRIPT_DIR/notarize.sh" "$APP_DIR"
fi

echo "[release] Creating distributable DMG at $DMG_PATH"
hdiutil create -volname "$APP_NAME" -srcfolder "$APP_DIR" -ov -format UDZO "$DMG_PATH"
codesign --force --timestamp --sign "$SIGNING_IDENTITY" "$DMG_PATH"

echo "[release] Build complete:"
echo "  App: $APP_DIR"
echo "  DMG: $DMG_PATH"
if [[ "${NOTARIZE:-0}" == "1" ]]; then
  echo "  Notarization: completed and stapled"
else
  echo "  Notarization: skipped (set NOTARIZE=1 to enable)"
fi
