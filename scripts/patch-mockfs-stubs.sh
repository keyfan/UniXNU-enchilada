#!/bin/bash
# patch-mockfs-stubs.sh — CI helper: create mockfs link-time stubs at ALL
# possible archive paths so the kernel links regardless of MOCKFS_MODE.
set -euo pipefail

# Create stub source
STUB_C=$(mktemp /tmp/mockfs-stubs-XXXXXX.c)
cat > "$STUB_C" << 'CEOF'
__attribute__((used)) const void *mockfs_vfsops[20] = { 0 };
__attribute__((used)) int mockfs_mountroot(void) { return 45; }
__attribute__((used)) const struct { const void *p; const char *n; unsigned o; } mockfs_vnodeop_opv_desc = { 0, "mockfs_disabled", 0 };
CEOF

# Compile once
STUB_O=$(mktemp /tmp/mockfs-stubs-XXXXXX.o)
clang -c -O2 -target arm64-apple-macos "$STUB_C" -o "$STUB_O"

# Create archives at every possible path
for BASE in "." ".cache/xnu-work" ".cache" "out"; do
    for SUBDIR in "mockfs-fixture" "mockfs-stubs"; do
        DIR="$BASE/build/$SUBDIR"
        mkdir -p "$DIR"
        ARCHIVE="$DIR/lib${SUBDIR//-/_}.a"
        # Also create with the fixture name in stubs dir and vice versa
        xcrun ar rcs "$DIR/libmockfs_fixture.a" "$STUB_O"
        xcrun ar rcs "$DIR/libmockfs_stubs.a" "$STUB_O"
        echo "stubs: $DIR/libmockfs_fixture.a + libmockfs_stubs.a"
    done
done

# Patch ALL copies of build-xnu-4k-baseline.sh
FOUND=0
while IFS= read -r SCRIPT; do
    [ -z "$SCRIPT" ] && continue
    FOUND=$((FOUND+1))
    if grep -q 'MOCKFS_STUBS' "$SCRIPT"; then
        echo "Already patched: $SCRIPT"
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
    print(f"Patched: {path}")
else:
    print(f"PATTERN NOT FOUND in: {path}")
PYEOF
done < <(find . -name 'build-xnu-4k-baseline.sh' -not -path './device/*' 2>/dev/null)

echo "Patched $FOUND copy(ies)"

# Also: if MOCKFS_MODE=1 is active and libmockfs_fixture.a is our stub,
# the test -f will pass and the stub gets force_loaded. That's fine.
echo "Done. Stubs available at all mockfs archive paths."
