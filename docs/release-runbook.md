# Waffle Release Runbook (GitHub + Sparkle)

This runbook defines the production release flow for Developer ID + Sparkle distribution via GitHub Releases.

## 1. Prerequisites

- Clean checkout of `main` (or release branch), with `swift test` passing.
- Apple Developer ID certificate installed locally.
- Xcode CLT available (`codesign`, `notarytool`, `stapler`, `hdiutil`).
- Sparkle `sign_update` available (default: `Sparkle/bin/sign_update`).
- Sparkle EdDSA private key file available locally.

## 2. Required Environment Variables

### Build + signing

- `SIGNING_IDENTITY` (required)
- `VERSION` (optional, defaults from `Info.plist`)

### Notarization

- `APPLE_ID`
- `TEAM_ID`
- `APP_SPECIFIC_PASSWORD`

### Sparkle signing / appcast

- `SPARKLE_PRIVATE_KEY_PATH` (required for update signing)
- `APPCAST_VERSION` (Sparkle build number, usually integer)
- `APPCAST_SHORT_VERSION` (human version)
- `APPCAST_DMG_URL` (public GitHub Release DMG URL)
- `APPCAST_PUB_DATE` (RFC 2822 date string)

## 3. Validate Release Config

```bash
./scripts/build-release.sh --validate-config
```

This fails if:
- `SUPublicEDKey` is missing or still placeholder.
- `SUFeedURL` is missing, non-HTTPS, or localhost/loopback.

## 4. Build, Sign, Notarize, Staple

```bash
SIGNING_IDENTITY="Developer ID Application: Example, Inc. (ABCDE12345)" \
VERSION="1.2.0" \
APPLE_ID="you@example.com" \
TEAM_ID="ABCDE12345" \
APP_SPECIFIC_PASSWORD="xxxx-xxxx-xxxx-xxxx" \
NOTARIZE=1 \
./scripts/build-release.sh
```

Outputs:
- `build/Waffle.app`
- `build/Waffle-<version>.dmg`

## 5. Binary Verification

```bash
codesign --verify --deep --strict build/Waffle.app
spctl --assess --type execute --verbose build/Waffle.app
codesign --verify --strict build/Waffle-1.2.0.dmg
```

## 6. Sparkle Sign + Generate Appcast

```bash
SPARKLE_PRIVATE_KEY_PATH="$HOME/.config/waffle/sparkle-private.pem" \
VERSION="1.2.0" \
GENERATE_APPCAST=1 \
APPCAST_VERSION="102" \
APPCAST_SHORT_VERSION="1.2.0" \
APPCAST_DMG_URL="https://github.com/<owner>/<repo>/releases/download/v1.2.0/Waffle-1.2.0.dmg" \
APPCAST_PUB_DATE="Mon, 30 Mar 2026 18:00:00 +0000" \
./scripts/sign-update.sh
```

Outputs:
- Sparkle signature metadata printed to terminal.
- `build/appcast.xml` ready to publish.

## 7. Publish GitHub Release Asset

1. Create GitHub Release tag (`v1.2.0`) and release notes.
2. Upload `build/Waffle-1.2.0.dmg` as asset.
3. Confirm the release asset URL exactly matches `APPCAST_DMG_URL`.

## 8. Publish Appcast

1. Publish `build/appcast.xml` to the appcast host URL configured in `SUFeedURL`.
2. Ensure host serves `application/xml` or `text/xml`.
3. Confirm published XML still references the released DMG URL and signature.

## 9. Update Check Sanity Test

On a machine with an older Waffle build:
1. Launch app.
2. Open Settings -> Updates.
3. Run `Check Now`.
4. Confirm new version is detected and download offer appears.

## 10. Rollback Procedure

If a bad release/appcast is published:

1. Immediately restore previous known-good appcast content at `SUFeedURL`.
2. If the bad DMG is on GitHub Release, remove the asset (or mark release as pre-release/draft and publish fixed asset under a new tag).
3. Re-run full build/sign/notarize/sign-update flow with incremented version/build.
4. Publish corrected appcast entry pointing to corrected asset.
5. Re-run update-check sanity on an older installed version.

Never reuse the same Sparkle version/build tuple for a corrected release.
