#!/bin/bash
# patch-mockfs-stubs.sh — Create mockfs stub archive AND patch build script
# so it links regardless of MOCKFS_MODE (0 or 1).
set -euo pipefail

# 1. Find build script and derive ROOT
SCRIPT=$(find . -name 'build-xnu-4k-baseline.sh' -not -path './device/*' 2>/dev/null | head -1)
[ -z "$SCRIPT" ] && echo "ERROR: build script not found" && exit 1
ROOT=$(cd "$(dirname "$SCRIPT")/.." && pwd)
echo "SCRIPT: $SCRIPT"
echo "ROOT: $ROOT"

# 2. Create stub archive at fixture path (for MOCKFS_MODE=1)
DIR="$ROOT/build/mockfs-fixture"
mkdir -p "$DIR"
cat > "$DIR/mockfs-stubs.c" << 'CEOF'
__attribute__((used)) const void *mockfs_vfsops[20] = { 0 };
__attribute__((used)) int mockfs_mountroot(void) { return 45; }
__attribute__((used)) const struct { const void *p; const char *n; unsigned o; } mockfs_vnodeop_opv_desc = { 0, "mockfs_disabled", 0 };
CEOF
clang -c -O2 -target arm64-apple-macos "$DIR/mockfs-stubs.c" -o "$DIR/mockfs-stubs.o"
xcrun ar rcs "$DIR/libmockfs_fixture.a" "$DIR/mockfs-stubs.o"
echo "Created: $DIR/libmockfs_fixture.a"

# 3. Also create at stubs path (for MOCKFS_MODE=0 with patched else branch)
DIR2="$ROOT/build/mockfs-stubs"
mkdir -p "$DIR2"
cp "$DIR/libmockfs_fixture.a" "$DIR2/libmockfs_stubs.a"
echo "Created: $DIR2/libmockfs_stubs.a"

# 4. Patch build script: add else branch for MOCKFS_MODE=0
if grep -q 'MOCKFS_STUBS' "$SCRIPT"; then
    echo "Build script already patched"
else
    python3 - "$SCRIPT" << 'PYEOF'
import sys
path = sys.argv[1]
text = open(path).read()
needle = '    KERNEL_ARCHIVE_DEPENDENCIES="$KERNEL_ARCHIVE_DEPENDENCIES $MOCKFS_ARCHIVE"\n  fi'
insert = '''    KERNEL_ARCHIVE_DEPENDENCIES="$KERNEL_ARCHIVE_DEPENDENCIES $MOCKFS_ARCHIVE"
  else
    MOCKFS_STUBS_ARCHIVE=$ROOT/build/mockfs-stubs/libmockfs_stubs.a
    test -f "$MOCKFS_STUBS_ARCHIVE"
    KERNEL_EXTRA_ARCHIVES="$KERNEL_EXTRA_ARCHIVES -Wl,-force_load,$MOCKFS_STUBS_ARCHIVE"
    KERNEL_ARCHIVE_DEPENDENCIES="$KERNEL_ARCHIVE_DEPENDENCIES $MOCKFS_STUBS_ARCHIVE"
  fi'''
if needle in text:
    text = text.replace(needle, insert, 1)
    open(path, 'w').write(text)
    print("PATCHED OK: added else branch for MOCKFS_MODE=0")
else:
    print("PATTERN NOT FOUND")
    sys.exit(1)
PYEOF
fi

echo "DONE: stubs at both paths + build script patched"
