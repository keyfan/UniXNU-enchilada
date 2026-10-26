#!/bin/bash
# patch-mockfs-stubs.sh — CI helper: create mockfs link-time stubs and patch
# ALL copies of build-xnu-4k-baseline.sh so the kernel links when XNU_SOURCE_MOCKFS=0.
set -euo pipefail

# 1. Build stub archive at multiple candidate locations
STUB_ARCHIVE_REL="build/mockfs-stubs/libmockfs_stubs.a"
for BASE in "." ".cache/xnu-work" ".cache" "out"; do
    STUB_DIR="$BASE/build/mockfs-stubs"
    mkdir -p "$STUB_DIR"
    cat > "$STUB_DIR/mockfs-stubs.c" << 'CEOF'
__attribute__((used)) const void *mockfs_vfsops[20] = { 0 };
__attribute__((used)) int mockfs_mountroot(void) { return 45; }
__attribute__((used)) const struct { const void *p; const char *n; unsigned o; } mockfs_vnodeop_opv_desc = { 0, "mockfs_disabled", 0 };
CEOF
    clang -c -O2 -target arm64-apple-macos "$STUB_DIR/mockfs-stubs.c" -o "$STUB_DIR/mockfs-stubs.o"
    xcrun ar rcs "$STUB_DIR/libmockfs_stubs.a" "$STUB_DIR/mockfs-stubs.o"
    echo "stubs: $STUB_DIR/libmockfs_stubs.a"
done

# 2. Patch ALL copies of build-xnu-4k-baseline.sh
FOUND=0
while IFS= read -r SCRIPT; do
    [ -z "$SCRIPT" ] && continue
    FOUND=$((FOUND+1))
    echo "Patching: $SCRIPT"
    if grep -q 'MOCKFS_STUBS' "$SCRIPT"; then
        echo "  Already patched"
        continue
    fi
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
    print("  PATCHED OK")
else:
    print("  PATTERN NOT FOUND")
PYEOF
done < <(find . -name 'build-xnu-4k-baseline.sh' -not -path './device/*' 2>/dev/null)

if [ "$FOUND" -eq 0 ]; then
    echo "ERROR: no build-xnu-4k-baseline.sh found"
    exit 1
fi
echo "Patched $FOUND copy(ies)"
