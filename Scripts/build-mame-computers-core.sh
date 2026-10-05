#!/usr/bin/env bash
# Build the home computers core (MAMEComputers.oecoreplugin) from source.
#
# Builds a small MAME that contains only the Apple //e, Apple IIgs, compact
# Macintosh (128K to Plus), Macintosh LC II, Commodore 64 and Commodore 128
# drivers (and the cards, drives and devices they need), as a headless dylib,
# then the OpenEmu core plugin around it. The one core serves OpenEmu's Apple IIe, Apple IIgs,
# Commodore 64, Commodore 128 and Macintosh systems.
#
# Usage:
#   ./Scripts/build-mame-computers-core.sh                # MAME 0.289 (default)
#   ./Scripts/build-mame-computers-core.sh --mame 0.250   # MAME 0.250 (OpenEmu's fork, as the Arcade core)
#   ./Scripts/install-core.sh MAMEComputers --release     # then install it
#
# The first build of each MAME version compiles a few hundred MAME source
# files and takes a while; later builds only recompile what changed. Each
# version keeps its own checkout (deps/mame, deps/mame-0289), so switching
# between them doesn't recompile MAME, only the core.

set -euo pipefail

MAME_VERSION="${MAME_COMPUTERS_VERSION:-0.289}"
while [ $# -gt 0 ]; do
  case "$1" in
    --mame) MAME_VERSION="${2:?--mame needs a version (0.250 or 0.289)}"; shift 2 ;;
    --mame=*) MAME_VERSION="${1#--mame=}"; shift ;;
    *) echo "error: unknown argument: $1" >&2; exit 2 ;;
  esac
done
case "$MAME_VERSION" in
  0.250|250) MAME_VERSION="0.250" ;;
  0.289|289) MAME_VERSION="0.289" ;;
  *) echo "error: unsupported MAME version '$MAME_VERSION' (use 0.250 or 0.289)" >&2; exit 2 ;;
esac

# The core's own revision; the bundle version is <MAME version>.<this>.
CORE_REVISION="9"

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

  MAME_BUILD_NO_REEXEC=1 "$TMP_REPO/Scripts/build-mame-computers-core.sh" --mame "$MAME_VERSION"

  rm -rf "$DD"
  mkdir -p "$(dirname "$DD")"
  rsync -a --delete "$TMP_REPO/MAMEComputers/build/XcodeDerived/" "$DD/"
  # Keep the compiled MAME tree so the next build is incremental.
  rsync -a --delete "$TMP_REPO/MAMEComputers/deps/" "$CORE_DIR/deps/"
  echo ""
  echo "Copied build products back to: $DD/Build/Products/Release/MAMEComputers.oecoreplugin"
  exit 0
fi

"$SCRIPT_DIR/prepare-mame-computers-core.sh" --mame "$MAME_VERSION"

# The real checkout (not the mame-active link), so MAME's dependency files
# always record the same paths.
MAME_SRC="$(cd -P "$CORE_DIR/deps/mame-active" && pwd)"
cd "$MAME_SRC"
make NOWERROR=1 REGENIE=1 macosx_arm64_clang \
  OSD="headless" verbose=1 TARGETOS="macosx" CONFIG="release" \
  TARGET=mame SUBTARGET=mamecomputers \
  SOURCES=src/mame/apple/apple2e.cpp,src/mame/apple/apple2gs.cpp,src/mame/apple/mac128.cpp,src/mame/apple/maclc.cpp,src/mame/commodore/c64.cpp,src/mame/commodore/c128.cpp \
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

# The Xcode project reads MAME's headers and dylib through deps/mame-active.
# Xcode can't tell that the files behind the link changed, so after switching
# MAME versions the core is rebuilt from scratch.
VERSION_STAMP="$DD/mamecomputers-mame-version"
if [ "$(cat "$VERSION_STAMP" 2>/dev/null || true)" != "$MAME_VERSION" ]; then
  echo "MAME version changed; rebuilding the core from scratch."
  rm -rf "$DD/Build/Intermediates.noindex/MAMEComputers.build" \
         "$DD/Build/Products/Release/MAMEComputers.oecoreplugin"
fi

xcodebuild \
  -project "$CORE_DIR/MAMEComputers.xcodeproj" \
  -scheme MAMEComputers \
  -configuration Release \
  -derivedDataPath "$DD" \
  ONLY_ACTIVE_ARCH=YES ARCHS=arm64 \
  CURRENT_PROJECT_VERSION="$MAME_VERSION.$CORE_REVISION" \
  build
echo "$MAME_VERSION" > "$VERSION_STAMP"

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
rsync -a "$MAME_SRC/plugins/" "$PLUGINS_DEST/"
# Plugins kept in this repo (they work with both MAME versions' Lua APIs).
rsync -a "$CORE_DIR/plugins/" "$PLUGINS_DEST/"
echo "MAME Lua plugins installed in: $PLUGINS_DEST"

echo ""
echo "Built: $PLUGIN (MAME $MAME_VERSION, version $MAME_VERSION.$CORE_REVISION)"
file "$PLUGIN/Contents/MacOS/MAMEComputers"
file "$PLUGIN/Contents/Frameworks/$DYLIB"
echo ""
echo "Install it with:  ./Scripts/install-core.sh MAMEComputers --release"
