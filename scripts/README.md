# Release Scripts

This directory contains the production release workflow for Waffle:

1. Validate Sparkle release config (`SUFeedURL`, `SUPublicEDKey`)
2. Build and sign a hardened-runtime `.app` bundle
3. (Optional) Submit for notarization and staple the ticket
4. Produce a signed `.dmg` for distribution
5. Sign the DMG for Sparkle and generate a publishable appcast

## Prerequisites

- Apple Developer account with a valid **Developer ID Application** certificate
- Xcode command-line tools (`codesign`, `notarytool`, `stapler`, `hdiutil`)
- Sparkle signing key pair (for appcast archive signatures)
- Access to publish files on your appcast host (for example GitHub Pages)

## Required Environment Variables

### Config validation

- `./scripts/build-release.sh --validate-config` checks:
  - `SUFeedURL` is non-empty, `https://`, and not localhost/loopback
  - `SUPublicEDKey` is non-empty and not `REPLACE_WITH_SPARKLE_PUBLIC_ED_KEY`
- Optional:
  - `INFO_PLIST_PATH_OVERRIDE` for validation against an alternate plist

### Build + signing

- `SIGNING_IDENTITY`
  - Example: `Developer ID Application: Example, Inc. (ABCDE12345)`
- `VERSION` (optional)
  - Defaults to `CFBundleShortVersionString` from `Sources/WaffleApp/Info.plist`
- Optional feed/key overrides:
  - `SU_FEED_URL_OVERRIDE`
  - `SPARKLE_PUBLIC_ED_KEY_OVERRIDE`

Production should keep `SUFeedURL` explicit in `Sources/WaffleApp/Info.plist`.
For staging/smoke releases, use override env vars at build time instead of editing the committed production URL.

### Notarization (required only when `NOTARIZE=1`)

- `APPLE_ID`
- `TEAM_ID`
- `APP_SPECIFIC_PASSWORD`

### Sparkle archive signing

- `SPARKLE_PRIVATE_KEY_PATH`
  - Path to the private EdDSA key generated with Sparkle's `generate_keys`
- `VERSION`
  - Used to locate `build/Waffle-${VERSION}.dmg`
- Optional:
  - `DMG_PATH_OVERRIDE` for alternate archive path
  - `GENERATE_APPCAST=1` to generate `build/appcast.xml` in the same command

## Build and Sign

```bash
./scripts/build-release.sh --validate-config

SIGNING_IDENTITY="Developer ID Application: Example, Inc. (ABCDE12345)" \
VERSION="1.0.0" \
./scripts/build-release.sh
```

Outputs:

- `build/Waffle.app`
- `build/Waffle-<version>.dmg`

## Build, Notarize, Staple, and Create DMG

```bash
SIGNING_IDENTITY="Developer ID Application: Example, Inc. (ABCDE12345)" \
APPLE_ID="you@example.com" \
TEAM_ID="ABCDE12345" \
APP_SPECIFIC_PASSWORD="xxxx-xxxx-xxxx-xxxx" \
VERSION="1.0.0" \
NOTARIZE=1 \
./scripts/build-release.sh
```

The script invokes `./scripts/notarize.sh` when `NOTARIZE=1`.

## Sparkle Archive Signature

After DMG creation, sign the update archive:

```bash
SPARKLE_PRIVATE_KEY_PATH="$HOME/.config/waffle/sparkle-private-key.pem" \
VERSION="1.0.0" \
./scripts/sign-update.sh
```

### Sign + generate appcast in one flow

```bash
SPARKLE_PRIVATE_KEY_PATH="$HOME/.config/waffle/sparkle-private-key.pem" \
VERSION="1.0.0" \
GENERATE_APPCAST=1 \
APPCAST_VERSION="100" \
APPCAST_SHORT_VERSION="1.0.0" \
APPCAST_DMG_URL="https://github.com/<owner>/<repo>/releases/download/v1.0.0/Waffle-1.0.0.dmg" \
APPCAST_PUB_DATE="Mon, 30 Mar 2026 18:00:00 +0000" \
./scripts/sign-update.sh
```

Generated output:
- `build/appcast.xml` (override via `APPCAST_OUTPUT_PATH`)

`scripts/sign-update.sh` parses Sparkle `edSignature`, computes archive length from the DMG, and calls `scripts/generate-appcast.sh`.

## Standalone Appcast Generation

```bash
APPCAST_VERSION="100" \
APPCAST_SHORT_VERSION="1.0.0" \
APPCAST_DMG_URL="https://github.com/<owner>/<repo>/releases/download/v1.0.0/Waffle-1.0.0.dmg" \
APPCAST_ED_SIGNATURE="<sparkle-signature>" \
APPCAST_ARCHIVE_LENGTH="123456789" \
APPCAST_MINIMUM_SYSTEM_VERSION="14.0" \
APPCAST_PUB_DATE="Mon, 30 Mar 2026 18:00:00 +0000" \
APPCAST_OUTPUT_PATH="build/appcast.xml" \
./scripts/generate-appcast.sh
```

`scripts/generate-appcast.sh` uses `tools/appcast-template.xml` and validates malformed version/URL/length input before writing output.
