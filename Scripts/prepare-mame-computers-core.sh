#!/usr/bin/env bash
# Prepare the MAME headless source used by MAMEComputers/MAMEComputers.xcodeproj.
#
# Uses the same pinned OpenEmu-Silicon/mame 0.250 revision as the Arcade core,
# checked out separately in MAMEComputers/deps/mame so the two builds (different
# driver lists) never share object files. If the Arcade core's checkout already
# exists it is used as the clone source, which avoids downloading MAME twice.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
CORE_DIR="$REPO_ROOT/MAMEComputers"
OLD_SRC_DIR="$REPO_ROOT/MAMEApple2/deps/mame"  # before the core was renamed
DEPS_DIR="$CORE_DIR/deps"
SRC_DIR="$DEPS_DIR/mame"
ARCADE_SRC_DIR="$REPO_ROOT/MAME/deps/mame"
REVISION="fac13e827b7b8cfa4ee4f5760198d31241e2a544"
REMOTE="https://github.com/OpenEmu-Silicon/mame.git"

# Applied in order on top of the pinned revision.
PATCHES=(
  "$REPO_ROOT/MAME/patches/mame-headless-clang21-apple.patch"
  "$CORE_DIR/patches/mame-headless-computers.patch"
)

mkdir -p "$DEPS_DIR"

# Reuse the checkout from when this core was called MAMEApple2.
if [ ! -e "$SRC_DIR" ] && [ -e "$OLD_SRC_DIR/.git" ]; then
  echo "Moving the existing MAME checkout from MAMEApple2/deps to MAMEComputers/deps..."
  mv "$OLD_SRC_DIR" "$SRC_DIR"
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

cd "$SRC_DIR"
git remote set-url origin "$REMOTE"

if ! git cat-file -e "$REVISION^{commit}" 2>/dev/null; then
  git fetch --no-tags origin "$REVISION"
fi

# Re-apply patches from a clean tree every time, so edits to a patch file are
# always picked up. Build outputs (build/, *.dylib) are untracked and survive.
git checkout --detach --force "$REVISION"
git reset --hard --quiet "$REVISION"

for patch in "${PATCHES[@]}"; do
  echo "Applying $(basename "$patch")..."
  if ! git apply --check "$patch"; then
    echo "error: patch does not apply cleanly: $patch" >&2
    exit 1
  fi
  git apply "$patch"
done

echo "MAME source ready at $SRC_DIR"
