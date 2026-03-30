# Release Scripts

This directory contains the production release workflow for Waffle:

1. Build and sign a hardened-runtime `.app` bundle
2. (Optional) Submit for notarization and staple the ticket
3. Produce a signed `.dmg` for distribution
4. Sign the DMG for Sparkle appcast publishing

## Prerequisites

- Apple Developer account with a valid **Developer ID Application** certificate
- Xcode command-line tools (`codesign`, `notarytool`, `stapler`, `hdiutil`)
- Sparkle signing key pair (for appcast archive signatures)
- Access to publish files on `updates.waffle.app`

## Required Environment Variables

### Build + signing

- `SIGNING_IDENTITY`
  - Example: `Developer ID Application: Example, Inc. (ABCDE12345)`
- `VERSION` (optional)
  - Defaults to `CFBundleShortVersionString` from `Sources/WaffleApp/Info.plist`

### Notarization (required only when `NOTARIZE=1`)

- `APPLE_ID`
- `TEAM_ID`
- `APP_SPECIFIC_PASSWORD`

### Sparkle archive signing

- `SPARKLE_PRIVATE_KEY_PATH`
  - Path to the private EdDSA key generated with Sparkle's `generate_keys`
- `VERSION`
  - Used to locate `build/Waffle-${VERSION}.dmg`

## Build and Sign

```bash
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

After DMG creation, generate Sparkle metadata:

```bash
SPARKLE_PRIVATE_KEY_PATH="$HOME/.config/waffle/sparkle-private-key.pem" \
VERSION="1.0.0" \
./scripts/sign-update.sh
```

Use the resulting `edSignature` and `length` in your appcast entry (see `tools/appcast-template.xml`).
