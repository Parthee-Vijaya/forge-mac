#!/bin/bash
# Build a distributable Forge.app + .dmg for personal/local use.
#
# Signing: ad-hoc ("-") WITH the entitlements applied (NOT unsigned). Forge spawns
# a `node` dev server that loads unsigned native addons (esbuild/Rollup/Tailwind
# oxide); under Hardened Runtime that only works if the app is signed with the
# `disable-library-validation` entitlement. So unlike a pure-Swift app we must
# keep signing ON — we just use the ad-hoc identity (no Developer ID needed).
#
# NOT notarized: that requires a "Developer ID Application" cert + Apple Developer
# Program membership (none on this machine). First launch therefore needs a
# right-click -> Open (or `xattr -dr com.apple.quarantine Forge.app`) to clear
# Gatekeeper. Notarized distribution is a follow-up once a Developer ID exists.
set -euo pipefail

cd "$(dirname "$0")/.."
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer

APP_NAME="Forge"
PROJECT="Forge.xcodeproj"
BUILD_DIR=".build-release"
VERSION="$(grep -m1 'MARKETING_VERSION' project.yml | sed 's/.*"\(.*\)".*/\1/' || echo 0.1.0)"
DMG_NAME="${APP_NAME}-${VERSION}.dmg"

echo "=== Regenerating project from project.yml ==="
command -v xcodegen >/dev/null 2>&1 && xcodegen generate

echo "=== Building ${APP_NAME} ${VERSION} (Release · arm64 · ad-hoc signed + entitlements) ==="
xcodebuild -project "$PROJECT" -scheme "$APP_NAME" -configuration Release \
    -arch arm64 ONLY_ACTIVE_ARCH=YES \
    -derivedDataPath "$BUILD_DIR" \
    clean build \
    CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="-" DEVELOPMENT_TEAM="" \
    | grep -E "(error:|BUILD SUCCEEDED|BUILD FAILED)" || true

APP_PATH="$(find "$BUILD_DIR/Build/Products/Release" -name "${APP_NAME}.app" -maxdepth 2 -type d | head -1)"
[ -z "$APP_PATH" ] && { echo "ERROR: ${APP_NAME}.app not found"; exit 1; }
echo "=== Built: $APP_PATH ==="

# Sanity-check the entitlement that lets node load native addons survived signing.
if codesign -d --entitlements - "$APP_PATH" 2>&1 | grep -q "disable-library-validation"; then
    echo "✓ disable-library-validation entitlement embedded"
else
    echo "⚠ WARNING: entitlement missing — the node dev server may fail to start"
fi

echo "=== Staging DMG ==="
STAGING="$BUILD_DIR/dmg-staging"
rm -rf "$STAGING"; mkdir -p "$STAGING"
cp -R "$APP_PATH" "$STAGING/"
ln -s /Applications "$STAGING/Applications"

rm -f "$DMG_NAME"
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGING" -ov -format UDZO "$DMG_NAME" >/dev/null

echo ""
echo "=== DMG created: $DMG_NAME ($(du -h "$DMG_NAME" | cut -f1)) ==="
echo "Install: open $DMG_NAME, drag ${APP_NAME} to Applications."
echo "First launch: right-click ${APP_NAME}.app -> Open (unsigned/not notarized)."
