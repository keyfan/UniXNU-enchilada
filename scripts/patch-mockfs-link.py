#!/usr/bin/env python3
"""Patch ALL copies of build-xnu-4k-baseline.sh to link the mockfs fixture."""
import sys
from pathlib import Path

needle = '''  EXTRA_MAKE_ARGS+=("LD_KERNEL_ARCHIVES=$KERNEL_EXTRA_ARCHIVES")
  EXTRA_MAKE_ARGS+=("XNU_EXTERNAL_KERNEL_ARCHIVES=$KERNEL_ARCHIVE_DEPENDENCIES")
fi'''

insert = '''  EXTRA_MAKE_ARGS+=("LD_KERNEL_ARCHIVES=$KERNEL_EXTRA_ARCHIVES")
  EXTRA_MAKE_ARGS+=("XNU_EXTERNAL_KERNEL_ARCHIVES=$KERNEL_ARCHIVE_DEPENDENCIES")
fi
# Always link mockfs fixture regardless of BOOTSTRAP mode.
MOCKFS_LINK="$ROOT/build/mockfs-fixture/libmockfs_fixture.a"
if [ -f "$MOCKFS_LINK" ]; then
  EXTRA_MAKE_ARGS+=("LD_KERNEL_ARCHIVES=-Wl,-force_load,$MOCKFS_LINK")
  EXTRA_MAKE_ARGS+=("XNU_EXTERNAL_KERNEL_ARCHIVES=$MOCKFS_LINK")
  echo "MOCKFS_FIXTURE_LINKED=$MOCKFS_LINK"
fi'''

found = 0
for script in Path('.').rglob('build-xnu-4k-baseline.sh'):
    if '.git' in str(script):
        continue
    text = script.read_text()
    if 'MOCKFS_FIXTURE_LINKED' in text:
        print(f"Already patched: {script}")
        found += 1
        continue
    if needle in text:
        text = text.replace(needle, insert, 1)
        script.write_text(text)
        print(f"PATCHED OK: {script}")
        found += 1
    else:
        print(f"PATTERN NOT FOUND in: {script}")

if found == 0:
    print("ERROR: no build-xnu-4k-baseline.sh found or patched")
    sys.exit(1)
print(f"Patched {found} copy(ies)")
