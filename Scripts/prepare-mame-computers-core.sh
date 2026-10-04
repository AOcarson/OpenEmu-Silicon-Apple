#!/usr/bin/env bash
# Prepare the MAME headless source used by MAMEComputers/MAMEComputers.xcodeproj.
#
# Usage:
#   ./Scripts/prepare-mame-computers-core.sh                # MAME 0.250 (default)
#   ./Scripts/prepare-mame-computers-core.sh --mame 0.289   # MAME 0.289
#
# MAME 0.250: the same pinned OpenEmu-Silicon/mame revision as the Arcade core,
# checked out separately in MAMEComputers/deps/mame so the two builds
# (different driver lists) never share object files. If the Arcade core's
# checkout already exists it is used as the clone source, which avoids
# downloading MAME twice.
#
# MAME 0.289: mamedev's mame0289 release in MAMEComputers/deps/mame-0289, with
# OpenEmu's headless OSD ported to it (patches/0289).
#
# Each version keeps its own checkout and compiled objects, so switching back
# and forth only rebuilds the core. MAMEComputers/deps/mame-active points at
# the selected one; the Xcode project reads MAME's headers and dylib from there.

set -euo pipefail

MAME_VERSION="${MAME_COMPUTERS_VERSION:-0.250}"
while [ $# -gt 0 ]; do
  case "$1" in
    --mame) MAME_VERSION="${2:?--mame needs a version (0.250 or 0.289)}"; shift 2 ;;
    --mame=*) MAME_VERSION="${1#--mame=}"; shift ;;
    *) echo "error: unknown argument: $1" >&2; exit 2 ;;
  esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
CORE_DIR="$REPO_ROOT/MAMEComputers"
DEPS_DIR="$CORE_DIR/deps"
ACTIVE_LINK="$DEPS_DIR/mame-active"

case "$MAME_VERSION" in
  0.250|250)
    MAME_VERSION="0.250"
    SRC_NAME="mame"
    REVISION="fac13e827b7b8cfa4ee4f5760198d31241e2a544"
    REMOTE="https://github.com/OpenEmu-Silicon/mame.git"
    FETCH_REF="$REVISION"
    PATCHES=(
      "$REPO_ROOT/MAME/patches/mame-headless-clang21-apple.patch"
      "$CORE_DIR/patches/mame-headless-computers.patch"
    )
    ;;
  0.289|289)
    MAME_VERSION="0.289"
    SRC_NAME="mame-0289"
    REVISION="mame0289"   # mamedev's release tag
    REMOTE="https://github.com/mamedev/mame.git"
    FETCH_REF="refs/tags/mame0289:refs/tags/mame0289"
    PATCHES=(
      "$CORE_DIR/patches/0289/mame-headless-openemu.patch"
      "$CORE_DIR/patches/0289/mame-headless-computers.patch"
    )
    ;;
  *)
    echo "error: unsupported MAME version '$MAME_VERSION' (use 0.250 or 0.289)" >&2
    exit 2
    ;;
esac

SRC_DIR="$DEPS_DIR/$SRC_NAME"
mkdir -p "$DEPS_DIR"

if [ "$MAME_VERSION" = "0.250" ]; then
  OLD_SRC_DIR="$REPO_ROOT/MAMEApple2/deps/mame"  # before the core was renamed
  ARCADE_SRC_DIR="$REPO_ROOT/MAME/deps/mame"

  # Reuse the checkout from when this core was called MAMEApple2.
  if [ ! -e "$SRC_DIR" ] && [ -e "$OLD_SRC_DIR/.git" ]; then
    echo "Moving the existing MAME checkout from MAMEApple2/deps to MAMEComputers/deps..."
    mv "$OLD_SRC_DIR" "$SRC_DIR"
    # Its compiled objects record their old absolute paths; start them fresh.
    rm -rf "$SRC_DIR/build"
    rmdir "$(dirname "$OLD_SRC_DIR")" "$(dirname "$(dirname "$OLD_SRC_DIR")")" 2>/dev/null || true
  fi

  if [ ! -e "$SRC_DIR/.git" ]; then
    if [ -e "$ARCADE_SRC_DIR/.git" ]; then
      echo "Cloning MAME from the Arcade core's checkout into $SRC_DIR..."
      git clone --no-tags --no-checkout "$ARCADE_SRC_DIR" "$SRC_DIR"
    else
      echo "Cloning OpenEmu-Silicon/mame into $SRC_DIR..."
      git clone --no-tags --no-checkout "$REMOTE" "$SRC_DIR"
    fi
  fi
else
  # MAME's full history is several GB; only the release itself is fetched.
  if [ ! -e "$SRC_DIR/.git" ]; then
    echo "Downloading MAME $MAME_VERSION into $SRC_DIR (one-time, a few hundred MB)..."
    git init --quiet "$SRC_DIR"
  fi
fi

cd "$SRC_DIR"
if git remote get-url origin >/dev/null 2>&1; then
  git remote set-url origin "$REMOTE"
else
  git remote add origin "$REMOTE"
fi

if ! git cat-file -e "$REVISION^{commit}" 2>/dev/null; then
  if [ "$MAME_VERSION" = "0.250" ]; then
    git fetch --no-tags origin "$FETCH_REF"
  else
    git fetch --no-tags --depth 1 origin "$FETCH_REF"
  fi
fi

# Re-apply patches from a clean tree every time, so edits to a patch file are
# always picked up. Build outputs (build/, *.dylib) are untracked and survive.
git checkout --quiet --detach --force "$REVISION"
git reset --hard --quiet "$REVISION"
# Files a patch adds aren't tracked, so the reset leaves them behind; remove
# them (and only them) so the patch can add them again.
for patch in "${PATCHES[@]}"; do
  git apply --numstat "$patch" | cut -f3-
done | sort -u | while IFS= read -r file; do
  if [ -n "$file" ] && ! git ls-files --error-unmatch -- "$file" >/dev/null 2>&1; then
    rm -f -- "$file"
  fi
done

for patch in "${PATCHES[@]}"; do
  echo "Applying $(basename "$(dirname "$patch")")/$(basename "$patch")..."
  if ! git apply --check --whitespace=nowarn "$patch"; then
    echo "error: patch does not apply cleanly: $patch" >&2
    exit 1
  fi
  git apply --whitespace=nowarn "$patch"
done

# Object files built before the checkout moved (from MAMEApple2/deps) name
# headers by their old absolute paths, which make then can't find. Clear them
# so everything is rebuilt from the current location.
if [ -d build ] && grep -rqsl --include='*.d' "/MAMEApple2/deps/mame/" build; then
  echo "Removing MAME objects built at the old MAMEApple2/deps location..."
  rm -rf build
fi

# Point the Xcode project at this version (a relative link, so the build's
# temporary no-space mirror keeps working).
if [ -e "$ACTIVE_LINK" ] && [ ! -L "$ACTIVE_LINK" ]; then
  echo "error: $ACTIVE_LINK exists and is not a symlink; move it aside" >&2
  exit 1
fi
ln -sfn "$SRC_NAME" "$ACTIVE_LINK"

echo "MAME $MAME_VERSION source ready at $SRC_DIR (deps/mame-active -> $SRC_NAME)"
