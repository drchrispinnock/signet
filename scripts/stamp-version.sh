#!/bin/sh
# Xcode post-build phase: stamp the built Info.plist with the version from git.
#   CFBundleShortVersionString = git describe --tags, without the leading "v"
#                                (e.g. 0.2 on the tag, 0.2-3-g58b56be three commits later, "-dirty" if uncommitted)
#   CFBundleVersion            = number of commits on this branch (monotonic build number)
# Falls back to whatever the project set when git is unavailable (e.g. building from a tarball).
set -eu
PLIST="${TARGET_BUILD_DIR}/${INFOPLIST_PATH}"
[ -f "$PLIST" ] || exit 0
if ! git -C "$SRCROOT" rev-parse --git-dir >/dev/null 2>&1; then
  echo "note: not a git checkout; leaving version as configured"
  exit 0
fi
VERSION="$(git -C "$SRCROOT" describe --tags --always --dirty 2>/dev/null | sed 's/^v//')"
BUILD="$(git -C "$SRCROOT" rev-list --count HEAD 2>/dev/null || echo 1)"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD" "$PLIST"
echo "Stamped Signet $VERSION (build $BUILD)"
