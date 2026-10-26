#!/bin/bash
# patch-mockfs-stubs.sh — CI helper: create mockfs link-time stubs and patch
# build-xnu-4k-baseline.sh so the kernel links when XNU_SOURCE_MOCKFS=0.
# Run from the CI workspace root before "./unixnu build kernel".
set -euo pipefail

STUB_DIR="out/build/mockfs-stubs"
mkdir -p "$STUB_DIR"

# 1. Compile the stubs
cat > "$STUB_DIR/mockfs-stubs.c" << 'CEOF'
__attribute__((used)) const void *mockfs_vfsops[20] = { 0 };
__attribute__((used)) int mockfs_mountroot(void) { return 45; }
__attribute__((used)) const struct { const void *p; const char *n; unsigned o; } mockfs_vnodeop_opv_desc = { 0, "mockfs_disabled", 0 };
CEOF
clang -c -O2 -target arm64-apple-macos "$STUB_DIR/mockfs-stubs.c" -o "$STUB_DIR/mockfs-stubs.o"
xcrun ar rcs "$STUB_DIR/libmockfs_stubs.a" "$STUB_DIR/mockfs-stubs.o"
echo "mockfs stubs archive built"

# 2. Find and patch build-xnu-4k-baseline.sh
SCRIPT=""
for candidate in \
    "$(find .cache -name 'build-xnu-4k-baseline.sh' 2>/dev/null | head -1)" \
    "$(find . -name 'build-xnu-4k-baseline.sh' -not -path './device/*' 2>/dev/null | head -1)"; do
    [ -n "$candidate" ] && SCRIPT="$candidate" && break
done
[ -z "$SCRIPT" ] && echo "ERROR: build-xnu-4k-baseline.sh not found" && exit 1
echo "Patching: $SCRIPT"

if grep -q 'MOCKFS_STUBS' "$SCRIPT"; then
    echo "Already patched, skipping"
    exit 0
fi

# 3. Insert the stub-linking else-branch after the MOCKFS_MODE=1 block
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
    print("PATCHED OK")
else:
    print("PATTERN NOT FOUND")
    sys.exit(1)
PYEOF
