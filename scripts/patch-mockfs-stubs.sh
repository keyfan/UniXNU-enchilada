#!/bin/bash
# patch-mockfs-stubs.sh — Create mockfs stub archive at the exact path
# build-xnu-4k-baseline.sh expects when MOCKFS_MODE=1.
set -euo pipefail

# Determine $ROOT the same way build-xnu-4k-baseline.sh does
SCRIPT=$(find . -name 'build-xnu-4k-baseline.sh' -not -path './device/*' 2>/dev/null | head -1)
[ -z "$SCRIPT" ] && echo "ERROR: build script not found" && exit 1
ROOT=$(cd "$(dirname "$SCRIPT")/.." && pwd)
echo "ROOT: $ROOT"

# Create stub archive at $ROOT/build/mockfs-fixture/libmockfs_fixture.a
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

# Verify
if [ -f "$DIR/libmockfs_fixture.a" ]; then
    echo "SUCCESS: mockfs stub archive ready"
else
    echo "ERROR: archive not created"
    exit 1
fi
