#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
APP_NAME="Waffle"
APP_DIR="$REPO_ROOT/build/${APP_NAME}.app"
ENTITLEMENTS="$REPO_ROOT/Sources/WaffleApp/WaffleApp.entitlements"
INFO_PLIST_SOURCE="${INFO_PLIST_PATH_OVERRIDE:-$REPO_ROOT/Sources/WaffleApp/Info.plist}"
PLACEHOLDER_SPARKLE_PUBLIC_KEY="REPLACE_WITH_SPARKLE_PUBLIC_ED_KEY"

print_usage() {
  cat <<'USAGE'
Usage: ./scripts/build-release.sh [--validate-config]

Options:
  --validate-config   Validate Sparkle release config in Info.plist and exit.
  -h, --help          Show this message.

Environment:
  SIGNING_IDENTITY                 Required for full build/sign flow.
  NOTARIZE=1                       Optional notarization pass.
  INFO_PLIST_PATH_OVERRIDE         Optional plist path override (testing/CI).
  SU_FEED_URL_OVERRIDE             Optional feed URL override applied at build time.
  SPARKLE_PUBLIC_ED_KEY_OVERRIDE   Optional Sparkle public key override at build time.
USAGE
}

trimmed_value() {
  local value="$1"
  echo "$value" | awk '{$1=$1;print}'
}

read_plist_value() {
  local plist_path="$1"
  local key="$2"
  /usr/libexec/PlistBuddy -c "Print :$key" "$plist_path" 2>/dev/null || true
}

validate_release_config() {
  local plist_path="$1"

  if [[ ! -f "$plist_path" ]]; then
    echo "error: missing Info.plist at $plist_path" >&2
    return 1
  fi

  local feed_url public_ed_key
  feed_url="$(read_plist_value "$plist_path" "SUFeedURL")"
  public_ed_key="$(read_plist_value "$plist_path" "SUPublicEDKey")"

  if [[ -n "${SU_FEED_URL_OVERRIDE:-}" ]]; then
    feed_url="${SU_FEED_URL_OVERRIDE}"
  fi

  if [[ -n "${SPARKLE_PUBLIC_ED_KEY_OVERRIDE:-}" ]]; then
    public_ed_key="${SPARKLE_PUBLIC_ED_KEY_OVERRIDE}"
  fi

  feed_url="$(trimmed_value "$feed_url")"
  public_ed_key="$(trimmed_value "$public_ed_key")"

  if [[ -z "$feed_url" ]]; then
    echo "error: SUFeedURL must be set to a production HTTPS appcast URL." >&2
    return 1
  fi

  if [[ "$feed_url" =~ [[:space:]] ]]; then
    echo "error: SUFeedURL must not contain whitespace." >&2
    return 1
  fi

  if [[ "$feed_url" != https://* ]]; then
    echo "error: SUFeedURL must be an https URL." >&2
    return 1
  fi

  if [[ "$feed_url" =~ ^https://(localhost|127\.0\.0\.1|::1)([:/]|$) ]]; then
    echo "error: SUFeedURL must not target localhost/loopback in release builds." >&2
    return 1
  fi

  if [[ -z "$public_ed_key" || "$public_ed_key" == "$PLACEHOLDER_SPARKLE_PUBLIC_KEY" ]]; then
    echo "error: SUPublicEDKey must be set to a non-placeholder Sparkle public key." >&2
    return 1
  fi

  echo "[release] configuration validation passed:"
  echo "  SUFeedURL=$feed_url"
  echo "  SUPublicEDKey=configured"
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  print_usage
  exit 0
fi

if [[ "${1:-}" == "--validate-config" ]]; then
  validate_release_config "$INFO_PLIST_SOURCE"
  exit 0
fi

if [[ -z "${SIGNING_IDENTITY:-}" ]]; then
  echo "error: SIGNING_IDENTITY is required (Developer ID Application certificate)." >&2
  exit 1
fi

if [[ ! -f "$ENTITLEMENTS" ]]; then
  echo "error: missing entitlements file at $ENTITLEMENTS" >&2
  exit 1
fi

validate_release_config "$INFO_PLIST_SOURCE"

cd "$REPO_ROOT"

echo "[release] Building WaffleApp in release mode..."
swift build -c release --product WaffleApp --disable-sandbox
BIN_DIR="$(swift build -c release --show-bin-path)"
BINARY="$BIN_DIR/WaffleApp"

if [[ ! -x "$BINARY" ]]; then
  echo "error: expected built binary at $BINARY" >&2
  exit 1
fi

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources" "$APP_DIR/Contents/Frameworks"

echo "[release] Assembling app bundle at $APP_DIR"
cp "$BINARY" "$APP_DIR/Contents/MacOS/WaffleApp"
cp "$INFO_PLIST_SOURCE" "$APP_DIR/Contents/Info.plist"

if [[ -n "${SU_FEED_URL_OVERRIDE:-}" ]]; then
  /usr/libexec/PlistBuddy -c "Set :SUFeedURL $SU_FEED_URL_OVERRIDE" "$APP_DIR/Contents/Info.plist"
fi

if [[ -n "${SPARKLE_PUBLIC_ED_KEY_OVERRIDE:-}" ]]; then
  /usr/libexec/PlistBuddy -c "Set :SUPublicEDKey $SPARKLE_PUBLIC_ED_KEY_OVERRIDE" "$APP_DIR/Contents/Info.plist"
fi

validate_release_config "$APP_DIR/Contents/Info.plist"

if [[ -d "$REPO_ROOT/worker" ]]; then
  cp -R "$REPO_ROOT/worker" "$APP_DIR/Contents/Resources/worker"
fi

CORE_BUNDLE="$(find "$BIN_DIR" -maxdepth 1 -type d -name '*_WaffleCore.bundle' -print -quit || true)"
if [[ -n "$CORE_BUNDLE" ]]; then
  cp -R "$CORE_BUNDLE" "$APP_DIR/Contents/Resources/"
else
  echo "warning: WaffleCore resource bundle not found in $BIN_DIR" >&2
fi

while IFS= read -r framework_path; do
  cp -R "$framework_path" "$APP_DIR/Contents/Frameworks/"
done < <(find "$BIN_DIR" -maxdepth 1 -type d -name '*.framework' | sort)

APP_BINARY="$APP_DIR/Contents/MacOS/WaffleApp"
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

echo "[release] Next steps:"
echo "  1) Sparkle archive signature + appcast:"
echo "     VERSION=\"$VERSION\" SPARKLE_PRIVATE_KEY_PATH=/path/to/sparkle-private.pem GENERATE_APPCAST=1 APPCAST_VERSION=\"$VERSION\" APPCAST_SHORT_VERSION=\"$VERSION\" APPCAST_DMG_URL=\"https://github.com/<owner>/<repo>/releases/download/v$VERSION/Waffle-$VERSION.dmg\" APPCAST_PUB_DATE=\"$(LC_ALL=C date -u '+%a, %d %b %Y %H:%M:%S +0000')\" ./scripts/sign-update.sh"
echo "  2) Upload build/Waffle-$VERSION.dmg to the GitHub Release."
echo "  3) Publish build/appcast.xml to your appcast host (for example GitHub Pages)."
