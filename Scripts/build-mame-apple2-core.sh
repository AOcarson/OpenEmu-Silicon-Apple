#!/usr/bin/env bash
# Build the Apple IIe core (MAMEApple2.oecoreplugin) from source.
#
# Builds a small MAME 0.250 that contains only the Apple //e drivers
# (src/mame/apple/apple2e.cpp and the cards/devices it needs), as a headless
# dylib, then the OpenEmu core plugin around it.
#
# Usage:
#   ./Scripts/build-mame-apple2-core.sh            # build
#   ./Scripts/install-core.sh MAMEApple2 --release  # then install it
#
# The first build compiles a few hundred MAME source files and takes a while;
# later builds only recompile what changed.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
CORE_DIR="$REPO_ROOT/MAMEApple2"
DD="$CORE_DIR/build/XcodeDerived"
DYLIB="mameapple2e_headless.dylib"

# MAME's project generator mishandles absolute paths containing spaces. If the
# checkout lives under such a path, build from a temporary no-space mirror and
# copy the products back (same approach as build-mame-core.sh).
if [[ -z "${MAME_BUILD_NO_REEXEC:-}" && "$REPO_ROOT" =~ [[:space:]] ]]; then
  TMP_ROOT="$(mktemp -d /tmp/openemu-mameapple2-build.XXXXXX)"
  TMP_REPO="$TMP_ROOT/repo"
  cleanup() { rm -rf "$TMP_ROOT"; }
  trap cleanup EXIT

  echo "Repository path contains whitespace; building from temporary path:"
  echo "  $TMP_REPO"
  mkdir -p "$TMP_REPO"
  rsync -a --delete \
    --exclude '.git' \
    --exclude 'MAME/deps' --exclude 'MAME/build' \
    --exclude 'MAMEApple2/build' \
    "$REPO_ROOT/" "$TMP_REPO/"

  MAME_BUILD_NO_REEXEC=1 "$TMP_REPO/Scripts/build-mame-apple2-core.sh"

  rm -rf "$DD"
  mkdir -p "$(dirname "$DD")"
  rsync -a --delete "$TMP_REPO/MAMEApple2/build/XcodeDerived/" "$DD/"
  # Keep the compiled MAME tree so the next build is incremental.
  rsync -a --delete "$TMP_REPO/MAMEApple2/deps/" "$CORE_DIR/deps/"
  echo ""
  echo "Copied build products back to: $DD/Build/Products/Release/MAMEApple2.oecoreplugin"
  exit 0
fi

"$SCRIPT_DIR/prepare-mame-apple2-core.sh"

cd "$CORE_DIR/deps/mame"
make NOWERROR=1 REGENIE=1 macosx_arm64_clang \
  OSD="headless" verbose=1 TARGETOS="macosx" CONFIG="release" \
  TARGET=mame SUBTARGET=mameapple2e SOURCES=src/mame/apple/apple2e.cpp \
  MACOSX_DEPLOYMENT_TARGET=11.0 \
  -j"$(sysctl -n hw.ncpu)"

if [ ! -f "$DYLIB" ]; then
  echo "error: MAME build finished but $DYLIB was not produced in $(pwd)" >&2
  ls -la *.dylib 2>/dev/null || true
  exit 1
fi

install_name_tool -id "$DYLIB" "$DYLIB"

xcodebuild \
  -project "$REPO_ROOT/OpenEmu-SDK/OpenEmu-SDK.xcodeproj" \
  -scheme OpenEmuBase \
  -configuration Release \
  -derivedDataPath "$DD" \
  ONLY_ACTIVE_ARCH=YES ARCHS=arm64 \
  build

xcodebuild \
  -project "$CORE_DIR/MAMEApple2.xcodeproj" \
  -scheme MAMEApple2 \
  -configuration Release \
  -derivedDataPath "$DD" \
  ONLY_ACTIVE_ARCH=YES ARCHS=arm64 \
  build

PLUGIN="$DD/Build/Products/Release/MAMEApple2.oecoreplugin"

# MAME's Lua plugin bootstrap (boot.lua) and stock plugins, matching this MAME
# version, go where the core looks for plugins. Your own plugin folders there
# are left alone; stock ones are updated.
PLUGINS_DEST="$HOME/Library/Application Support/OpenEmu/MAMEApple2/plugins"
mkdir -p "$PLUGINS_DEST"
rsync -a "$CORE_DIR/deps/mame/plugins/" "$PLUGINS_DEST/"
echo "MAME Lua plugins installed in: $PLUGINS_DEST"

echo ""
echo "Built: $PLUGIN"
file "$PLUGIN/Contents/MacOS/MAMEApple2"
file "$PLUGIN/Contents/Frameworks/$DYLIB"
echo ""
echo "Install it with:  ./Scripts/install-core.sh MAMEApple2 --release"
