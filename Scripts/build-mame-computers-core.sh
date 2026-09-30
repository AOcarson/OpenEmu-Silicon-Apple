#!/usr/bin/env bash
# Build the home computers core (MAMEComputers.oecoreplugin) from source.
#
# Builds a small MAME 0.250 that contains only the Apple //e, Apple IIgs,
# Commodore 64 and Commodore 128 drivers (and the cards, drives and devices
# they need), as a headless dylib, then the OpenEmu core plugin around it.
# The one core serves OpenEmu's Apple IIe, Apple IIgs, Commodore 64 and
# Commodore 128 systems.
#
# Usage:
#   ./Scripts/build-mame-computers-core.sh             # build
#   ./Scripts/install-core.sh MAMEComputers --release  # then install it
#
# The first build compiles a few hundred MAME source files and takes a while;
# later builds only recompile what changed.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
CORE_DIR="$REPO_ROOT/MAMEComputers"
DD="$CORE_DIR/build/XcodeDerived"
DYLIB="mamecomputers_headless.dylib"
OE_SUPPORT="$HOME/Library/Application Support/OpenEmu"

# MAME's project generator mishandles absolute paths containing spaces. If the
# checkout lives under such a path, build from a temporary no-space mirror and
# copy the products back (same approach as build-mame-core.sh).
if [[ -z "${MAME_BUILD_NO_REEXEC:-}" && "$REPO_ROOT" =~ [[:space:]] ]]; then
  TMP_ROOT="$(mktemp -d /tmp/openemu-mamecomputers-build.XXXXXX)"
  TMP_REPO="$TMP_ROOT/repo"
  cleanup() { rm -rf "$TMP_ROOT"; }
  trap cleanup EXIT

  echo "Repository path contains whitespace; building from temporary path:"
  echo "  $TMP_REPO"
  mkdir -p "$TMP_REPO"
  rsync -a --delete \
    --exclude '.git' \
    --exclude 'MAME/deps' --exclude 'MAME/build' \
    --exclude 'MAMEComputers/build' --exclude 'MAMEApple2' \
    "$REPO_ROOT/" "$TMP_REPO/"

  MAME_BUILD_NO_REEXEC=1 "$TMP_REPO/Scripts/build-mame-computers-core.sh"

  rm -rf "$DD"
  mkdir -p "$(dirname "$DD")"
  rsync -a --delete "$TMP_REPO/MAMEComputers/build/XcodeDerived/" "$DD/"
  # Keep the compiled MAME tree so the next build is incremental.
  rsync -a --delete "$TMP_REPO/MAMEComputers/deps/" "$CORE_DIR/deps/"
  echo ""
  echo "Copied build products back to: $DD/Build/Products/Release/MAMEComputers.oecoreplugin"
  exit 0
fi

"$SCRIPT_DIR/prepare-mame-computers-core.sh"

cd "$CORE_DIR/deps/mame"
make NOWERROR=1 REGENIE=1 macosx_arm64_clang \
  OSD="headless" verbose=1 TARGETOS="macosx" CONFIG="release" \
  TARGET=mame SUBTARGET=mamecomputers \
  SOURCES=src/mame/apple/apple2e.cpp,src/mame/apple/apple2gs.cpp,src/mame/commodore/c64.cpp,src/mame/commodore/c128.cpp \
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
  -project "$CORE_DIR/MAMEComputers.xcodeproj" \
  -scheme MAMEComputers \
  -configuration Release \
  -derivedDataPath "$DD" \
  ONLY_ACTIVE_ARCH=YES ARCHS=arm64 \
  build

PLUGIN="$DD/Build/Products/Release/MAMEComputers.oecoreplugin"

# MAME's Lua plugin bootstrap (boot.lua) and stock plugins, matching this MAME
# version, go where the core looks for plugins. Your own plugin folders there
# are left alone; stock ones are updated.
# Until 0.250.2 this core was "MAMEApple2" (Apple IIe only). Carry its support
# folder (ROMs, per-game settings, MAME cfg/nvram, plugins) over, and remove
# the old core: both would otherwise claim the Apple IIe system.
if [ -d "$OE_SUPPORT/MAMEApple2" ] && [ ! -e "$OE_SUPPORT/MAMEComputers" ]; then
  mv "$OE_SUPPORT/MAMEApple2" "$OE_SUPPORT/MAMEComputers"
  echo "Moved $OE_SUPPORT/MAMEApple2 to $OE_SUPPORT/MAMEComputers"
fi
if [ -d "$OE_SUPPORT/Cores/MAMEApple2.oecoreplugin" ]; then
  if pgrep -xq OpenEmu; then
    echo "Quitting OpenEmu to remove the old MAMEApple2 core..."
    osascript -e 'quit app "OpenEmu"' || true
    sleep 2
  fi
  rm -rf "$OE_SUPPORT/Cores/MAMEApple2.oecoreplugin"
  echo "Removed the old MAMEApple2 core (replaced by MAMEComputers)."
fi

PLUGINS_DEST="$OE_SUPPORT/MAMEComputers/plugins"
mkdir -p "$PLUGINS_DEST"
rsync -a "$CORE_DIR/deps/mame/plugins/" "$PLUGINS_DEST/"
# Plugins kept in this repo (ported to MAME 0.250's Lua API).
rsync -a "$CORE_DIR/plugins/" "$PLUGINS_DEST/"
echo "MAME Lua plugins installed in: $PLUGINS_DEST"

echo ""
echo "Built: $PLUGIN"
file "$PLUGIN/Contents/MacOS/MAMEComputers"
file "$PLUGIN/Contents/Frameworks/$DYLIB"
echo ""
echo "Install it with:  ./Scripts/install-core.sh MAMEComputers --release"
