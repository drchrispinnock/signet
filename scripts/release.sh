#!/bin/sh
# Builds a Release copy of Signet and zips it for distribution.
#
#   scripts/release.sh [version]
#
# version defaults to the current git tag (v0.1 -> 0.1) or MARKETING_VERSION.
#
# Optional environment:
#   DEVELOPER_ID     "Developer ID Application: Name (TEAMID)" — signs the app for distribution.
#   NOTARY_PROFILE   keychain profile created with `xcrun notarytool store-credentials` — notarises
#                    and staples the app (requires DEVELOPER_ID).
#   SPARKLE_PRIVATE_KEY  the EdDSA private key (`generate_keys -x`) for signing the Sparkle
#                    appcast. Unset, the key in the login keychain is used; if there is none the
#                    appcast step is skipped.
#   SPARKLE_APPCAST  set to 0 to skip the appcast altogether.
#
# Without DEVELOPER_ID the app is ad-hoc signed: it runs locally and for testers who right-click
# and choose Open, but Gatekeeper will warn anyone who simply double-clicks a download.
#
# Output: dist/Signet-<version>.zip and dist/appcast.xml (the Sparkle feed, pointing at the zip on
# the GitHub release for this version). A dist/Signet-<version>.md, if present, becomes the
# release notes shown in the update dialog.
set -eu

cd "$(dirname "$0")/.."

VERSION="${1:-}"
if [ -z "$VERSION" ]; then
  TAG="$(git describe --tags --exact-match 2>/dev/null || true)"
  VERSION="${TAG#v}"
fi
if [ -z "$VERSION" ]; then
  VERSION="$(sed -n 's/^ *MARKETING_VERSION: *"\{0,1\}\([0-9.]*\).*/\1/p' project.yml | head -1)"
fi
BUILD_NUMBER="$(git rev-list --count HEAD 2>/dev/null || echo 1)"

DIST="dist"
WORK="build/release"
ARCHIVE="$WORK/Signet.xcarchive"
APP="$WORK/Signet.app"
ZIP="$DIST/Signet-$VERSION.zip"
PACKAGES="build/packages"   # SPM checkouts; the Sparkle artifact carries generate_appcast
REPO_URL="https://github.com/drchrispinnock/signet"

echo "==> Signet $VERSION (build $BUILD_NUMBER)"
rm -rf "$WORK" "$ZIP" "$DIST/appcast.xml" "$DIST/old_updates"
mkdir -p "$DIST"

if ! [ -d Signet.xcodeproj ]; then
  echo "==> Generating Xcode project"
  xcodegen generate
fi

echo "==> Archiving (Release)"
xcodebuild -project Signet.xcodeproj -scheme Signet -configuration Release \
  -destination 'platform=macOS' -archivePath "$ARCHIVE" \
  -clonedSourcePackagesDirPath "$PACKAGES" \
  MARKETING_VERSION="$VERSION" CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
  CODE_SIGN_IDENTITY="${DEVELOPER_ID:--}" CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM="" \
  archive 2>&1 | grep -E "error:|warning: .*Signet/|\*\* ARCHIVE" || true
[ -d "$ARCHIVE/Products/Applications/Signet.app" ] || { echo "archive failed"; exit 1; }
cp -R "$ARCHIVE/Products/Applications/Signet.app" "$APP"

if [ -n "${DEVELOPER_ID:-}" ]; then
  echo "==> Signing with $DEVELOPER_ID"
  codesign --force --deep --options runtime --timestamp \
    --entitlements Signet/Signet.entitlements --sign "$DEVELOPER_ID" "$APP"
fi
codesign --verify --deep --strict "$APP"
echo "    $(codesign -dv "$APP" 2>&1 | grep -E '^(Authority|Signature)' | head -1)"

zip_app() {
  rm -f "$ZIP"
  ditto -c -k --keepParent "$APP" "$ZIP"
}
zip_app

if [ -n "${NOTARY_PROFILE:-}" ]; then
  [ -n "${DEVELOPER_ID:-}" ] || { echo "NOTARY_PROFILE needs DEVELOPER_ID"; exit 1; }
  echo "==> Notarising"
  xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$APP"
  zip_app
fi

echo "==> $(du -h "$ZIP" | cut -f1) $ZIP"

# Sparkle appcast: one item for this release, signed with the EdDSA key, downloading from the
# GitHub release's assets. Release notes come from dist/Signet-<version>.md when the workflow
# (or you) put one there. Old zips in dist/ would be swept into old_updates/, so only this
# version's zip is offered to generate_appcast.
if [ "${SPARKLE_APPCAST:-1}" != 0 ]; then
  GENERATE_APPCAST="$PACKAGES/artifacts/sparkle/Sparkle/bin/generate_appcast"
  [ -x "$GENERATE_APPCAST" ] || { echo "generate_appcast not found under $PACKAGES"; exit 1; }
  FEED="$WORK/appcast"
  rm -rf "$FEED"; mkdir -p "$FEED"
  cp "$ZIP" "$FEED/"
  [ -f "$DIST/Signet-$VERSION.md" ] && cp "$DIST/Signet-$VERSION.md" "$FEED/"
  echo "==> Sparkle appcast"
  if [ -n "${SPARKLE_PRIVATE_KEY:-}" ]; then
    printf '%s' "$SPARKLE_PRIVATE_KEY" | "$GENERATE_APPCAST" --ed-key-file - \
      --download-url-prefix "$REPO_URL/releases/download/v$VERSION/" \
      --link "$REPO_URL/releases" \
      --full-release-notes-url "$REPO_URL/releases/tag/v$VERSION" \
      --embed-release-notes "$FEED"
  elif "$GENERATE_APPCAST" --account ed25519 \
      --download-url-prefix "$REPO_URL/releases/download/v$VERSION/" \
      --link "$REPO_URL/releases" \
      --full-release-notes-url "$REPO_URL/releases/tag/v$VERSION" \
      --embed-release-notes "$FEED"; then
    :
  else
    echo "    no Sparkle key available; skipping appcast (set SPARKLE_PRIVATE_KEY or run generate_keys)"
  fi
  if [ -f "$FEED/appcast.xml" ]; then
    cp "$FEED/appcast.xml" "$DIST/appcast.xml"
    echo "==> $DIST/appcast.xml"
  fi
fi
