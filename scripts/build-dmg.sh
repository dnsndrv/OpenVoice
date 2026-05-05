#!/usr/bin/env bash
# Builds OpenVoice.app (Release) and packages it into dist/OpenVoice.dmg
# ready for upload to GitHub Releases.
#
# The app is signed with the same persistent self-signed certificate that
# scripts/install.sh creates — that's enough to run on the local machine
# but Gatekeeper on other machines will still prompt. End users have to
# clear the quarantine flag once after install:
#
#     xattr -dr com.apple.quarantine /Applications/OpenVoice.app
#
# (This is the same dance every unsigned macOS app requires; it's the
# trade-off we make for not having a paid Apple Developer account.)

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
XCODEPROJ="$PROJECT_DIR/OpenVoice/OpenVoice.xcodeproj"
DIST="$PROJECT_DIR/dist"
APP_NAME="OpenVoice.app"
DMG_NAME="OpenVoice.dmg"
SIGN_IDENTITY="OpenVoice Local Signer"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

mkdir -p "$DIST"
rm -f "$DIST/$DMG_NAME"

# Reuse the install script's certificate setup — it's idempotent.
"$PROJECT_DIR/scripts/install.sh" >/dev/null 2>&1 || true

echo "▶ Build OpenVoice (Release)"
DERIVED="$(mktemp -d)"
trap 'rm -rf "$DERIVED"' EXIT

xcodebuild \
    -project "$XCODEPROJ" \
    -scheme OpenVoice \
    -configuration Release \
    -derivedDataPath "$DERIVED" \
    -destination 'platform=macOS' \
    build \
    > "$DERIVED/build.log" 2>&1 || {
        echo "Build failed. Log: $DERIVED/build.log" >&2
        tail -40 "$DERIVED/build.log" >&2
        exit 1
    }

BUILT_APP="$DERIVED/Build/Products/Release/$APP_NAME"

# Sign with the persistent local certificate so the app is at least
# verifiable on the developer's machine and TCC-stable.
SHA1="$(security find-certificate -c "$SIGN_IDENTITY" -Z "$KEYCHAIN" 2>/dev/null \
    | awk -F': ' '/SHA-1/ {print $2; exit}')"
if [[ -z "$SHA1" ]]; then
    echo "WARNING: signing certificate not found, leaving ad-hoc signature" >&2
else
    echo "▶ Sign with $SIGN_IDENTITY"
    codesign \
        --force \
        --deep \
        --sign "$SHA1" \
        --options=runtime \
        --entitlements "$PROJECT_DIR/OpenVoice/OpenVoice/OpenVoice.entitlements" \
        "$BUILT_APP"
fi

# Stage a folder with App + symlink to /Applications so the DMG looks like
# a standard installer.
STAGING="$(mktemp -d)"
trap 'rm -rf "$DERIVED" "$STAGING"' EXIT
ditto "$BUILT_APP" "$STAGING/$APP_NAME"
ln -s /Applications "$STAGING/Applications"

echo "▶ Create DMG → $DIST/$DMG_NAME"
hdiutil create \
    -volname "OpenVoice" \
    -srcfolder "$STAGING" \
    -ov \
    -format UDZO \
    "$DIST/$DMG_NAME" \
    >/dev/null

echo
echo "✅ $DIST/$DMG_NAME"
ls -lh "$DIST/$DMG_NAME"
