#!/usr/bin/env bash
# build-for-worktree.sh — Build OpenEmu to a stable per-branch path so
# macOS privacy permissions persist across rebuilds of the same branch.
#
# Why: macOS binds permissions (Input Monitoring, Accessibility, etc.) to
# a specific app path + code signature. Xcode's default DerivedData uses a
# random hash per checkout — every fresh worktree = different path = lost
# permissions. This script forces a stable path: ~/Builds/openemu/<branch>/.
#
# Usage:
#   ./Scripts/build-for-worktree.sh                  # builds the OpenEmu scheme
#   ./Scripts/build-for-worktree.sh "OpenEmu + FCEU" # builds a specific scheme
#   ./Scripts/build-for-worktree.sh --release        # Release configuration
#
# Signing: if an "Apple Development" certificate is in your keychain (add a
# free Apple ID in Xcode > Settings > Accounts > Manage Certificates), the
# build is signed with it. macOS then recognises each new build as the same
# app, so Input Monitoring stays granted across rebuilds. Without one the
# build is ad-hoc signed, and macOS asks again after every build.
#
# After building once, grant Input Monitoring (and any other permissions you
# need) to the printed app path in System Settings → Privacy & Security.
# Subsequent builds of the same branch land at the same path and inherit
# the granted permissions automatically.
#
# See docs/worktree-workflow.md for the full workflow and known caveats.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
cd "$REPO_ROOT"

WORKSPACE="OpenEmu-metal.xcworkspace"
CONFIG="Debug"
SCHEME="OpenEmu"
for arg in "$@"; do
  case "$arg" in
    --release) CONFIG="Release" ;;
    --debug)   CONFIG="Debug" ;;
    *)         SCHEME="$arg" ;;
  esac
done

BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null | sed 's|/|-|g')
if [ -z "$BRANCH" ] || [ "$BRANCH" = "HEAD" ]; then
  echo "error: cannot determine branch name (detached HEAD or not a git repo)" >&2
  exit 1
fi

BUILD_DIR="$HOME/Builds/openemu/$BRANCH"
mkdir -p "$BUILD_DIR"

# Resolve a stable Apple Development signing identity if available, and sign
# with it during the build (so every target keeps its own entitlements).
# Falls back to ad-hoc (-) if no such certificate is in the keychain.
SIGN_ID=$(security find-identity -v -p codesigning 2>/dev/null | awk -F'"' '/Apple Development/ {print $2; exit}')
SIGN_ARGS=()
if [ -n "$SIGN_ID" ]; then
  TEAM_ID=$(security find-certificate -c "$SIGN_ID" -p 2>/dev/null \
    | openssl x509 -noout -subject 2>/dev/null \
    | sed -n 's/.*OU *= *\([A-Z0-9]\{10\}\).*/\1/p')
  SIGN_ARGS=(CODE_SIGN_IDENTITY="$SIGN_ID" CODE_SIGN_STYLE=Manual)
  if [ -n "$TEAM_ID" ]; then
    SIGN_ARGS+=(DEVELOPMENT_TEAM="$TEAM_ID")
  fi
else
  SIGN_ID="-"
fi

echo "Building scheme '$SCHEME' ($CONFIG) for branch '$BRANCH'"
echo "Output: $BUILD_DIR/Build/Products/$CONFIG/"
echo "Signing: $SIGN_ID"
echo ""

xcodebuild \
  -workspace "$WORKSPACE" \
  -scheme "$SCHEME" \
  -configuration "$CONFIG" \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath "$BUILD_DIR" \
  ${SIGN_ARGS[@]+"${SIGN_ARGS[@]}"} \
  build
BUILD_STATUS=$?

APP_PATH="$BUILD_DIR/Build/Products/$CONFIG/OpenEmu.app"
if [ "$BUILD_STATUS" -ne 0 ]; then
  echo "" >&2
  echo "error: the build FAILED (xcodebuild exit $BUILD_STATUS); see the errors above." >&2
  echo "Any OpenEmu.app already at $APP_PATH is from an earlier build." >&2
  exit "$BUILD_STATUS"
fi
if [ -d "$APP_PATH" ]; then
  echo ""
  echo "System plugins in this build:"
  ls "$APP_PATH/Contents/PlugIns/Systems/" 2>/dev/null | sed 's/^/  /'
  echo ""
  echo "===================="
  echo "Build complete."
  echo "App:    $APP_PATH"
  echo "Signed: $SIGN_ID"
  echo ""
  echo "Launch:  open '$APP_PATH'"
  echo ""
  echo "First time on this branch? Grant Input Monitoring + any other"
  echo "permissions you need in System Settings → Privacy & Security."
  echo "Permissions persist for this branch's path across rebuilds."
  echo "===================="
else
  echo "warning: expected app at $APP_PATH but it doesn't exist" >&2
  echo "(scheme '$SCHEME' may not produce OpenEmu.app — check the Build/Products/$CONFIG dir)" >&2
  ls "$BUILD_DIR/Build/Products/$CONFIG/" 2>/dev/null || true
fi
