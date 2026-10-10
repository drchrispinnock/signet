#!/bin/bash
# Build and launch an isolated frontend demo with sample accounts.
set -euo pipefail
SIGNET_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
mkdir -p "$SIGNET_ROOT/build"
xcodebuild -project "$SIGNET_ROOT/Signet.xcodeproj" -scheme Signet \
  -destination 'platform=macOS' -derivedDataPath "$SIGNET_ROOT/build/demo" \
  PRODUCT_BUNDLE_IDENTIFIER=org.tezos.signet.demo build \
  > "$SIGNET_ROOT/build/demo-build.log" 2>&1 || {
    tail -n 40 "$SIGNET_ROOT/build/demo-build.log"
    exit 1
  }
open "$SIGNET_ROOT/build/demo/Build/Products/Debug/Signet.app" --args --demo -appearance dark -showsDisclaimer NO
