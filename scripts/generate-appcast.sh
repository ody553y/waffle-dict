#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TEMPLATE_PATH="${APPCAST_TEMPLATE_PATH:-$REPO_ROOT/tools/appcast-template.xml}"
OUTPUT_PATH="${APPCAST_OUTPUT_PATH:-$REPO_ROOT/build/appcast.xml}"

required_env_vars=(
  APPCAST_VERSION
  APPCAST_SHORT_VERSION
  APPCAST_DMG_URL
  APPCAST_ED_SIGNATURE
  APPCAST_ARCHIVE_LENGTH
  APPCAST_MINIMUM_SYSTEM_VERSION
  APPCAST_PUB_DATE
)

for variable_name in "${required_env_vars[@]}"; do
  if [[ -z "${!variable_name:-}" ]]; then
    echo "error: $variable_name is required." >&2
    exit 1
  fi
done

if [[ ! -f "$TEMPLATE_PATH" ]]; then
  echo "error: appcast template not found at $TEMPLATE_PATH" >&2
  exit 1
fi

if [[ "$APPCAST_VERSION" =~ [^0-9] ]]; then
  echo "error: APPCAST_VERSION must contain digits only." >&2
  exit 1
fi

if [[ ! "$APPCAST_SHORT_VERSION" =~ ^[0-9]+(\.[0-9]+){1,3}([-.][A-Za-z0-9]+)?$ ]]; then
  echo "error: APPCAST_SHORT_VERSION must be a dotted version string." >&2
  exit 1
fi

if [[ ! "$APPCAST_DMG_URL" =~ ^https?:// ]]; then
  echo "error: APPCAST_DMG_URL must be an absolute http(s) URL." >&2
  exit 1
fi

if [[ "$APPCAST_ED_SIGNATURE" =~ [[:space:]] ]]; then
  echo "error: APPCAST_ED_SIGNATURE must not contain whitespace." >&2
  exit 1
fi

if [[ ! "$APPCAST_ARCHIVE_LENGTH" =~ ^[0-9]+$ ]]; then
  echo "error: APPCAST_ARCHIVE_LENGTH must be a positive integer." >&2
  exit 1
fi

if [[ "$APPCAST_ARCHIVE_LENGTH" -le 0 ]]; then
  echo "error: APPCAST_ARCHIVE_LENGTH must be greater than zero." >&2
  exit 1
fi

if [[ ! "$APPCAST_MINIMUM_SYSTEM_VERSION" =~ ^[0-9]+(\.[0-9]+){1,2}$ ]]; then
  echo "error: APPCAST_MINIMUM_SYSTEM_VERSION must be a dotted version (for example 14.0)." >&2
  exit 1
fi

xml_escape() {
  local value="$1"
  value="${value//&/&amp;}"
  value="${value//</&lt;}"
  value="${value//>/&gt;}"
  value="${value//\"/&quot;}"
  value="${value//\'/&apos;}"
  echo "$value"
}

escape_replacement() {
  local value="$1"
  value="${value//\\/\\\\}"
  value="${value//|/\\|}"
  value="${value//&/\\&}"
  echo "$value"
}

APPCAST_VERSION_ESCAPED="$(escape_replacement "$(xml_escape "$APPCAST_VERSION")")"
APPCAST_SHORT_VERSION_ESCAPED="$(escape_replacement "$(xml_escape "$APPCAST_SHORT_VERSION")")"
APPCAST_DMG_URL_ESCAPED="$(escape_replacement "$(xml_escape "$APPCAST_DMG_URL")")"
APPCAST_ED_SIGNATURE_ESCAPED="$(escape_replacement "$(xml_escape "$APPCAST_ED_SIGNATURE")")"
APPCAST_ARCHIVE_LENGTH_ESCAPED="$(escape_replacement "$(xml_escape "$APPCAST_ARCHIVE_LENGTH")")"
APPCAST_MIN_SYSTEM_ESCAPED="$(escape_replacement "$(xml_escape "$APPCAST_MINIMUM_SYSTEM_VERSION")")"
APPCAST_PUB_DATE_ESCAPED="$(escape_replacement "$(xml_escape "$APPCAST_PUB_DATE")")"

mkdir -p "$(dirname "$OUTPUT_PATH")"

sed \
  -e "s|{VERSION}|$APPCAST_VERSION_ESCAPED|g" \
  -e "s|{SHORT_VERSION}|$APPCAST_SHORT_VERSION_ESCAPED|g" \
  -e "s|{DMG_URL}|$APPCAST_DMG_URL_ESCAPED|g" \
  -e "s|{ED_SIGNATURE}|$APPCAST_ED_SIGNATURE_ESCAPED|g" \
  -e "s|{LENGTH}|$APPCAST_ARCHIVE_LENGTH_ESCAPED|g" \
  -e "s|{MINIMUM_SYSTEM_VERSION}|$APPCAST_MIN_SYSTEM_ESCAPED|g" \
  -e "s|{DATE}|$APPCAST_PUB_DATE_ESCAPED|g" \
  "$TEMPLATE_PATH" >"$OUTPUT_PATH"

echo "[appcast] Generated $OUTPUT_PATH"
