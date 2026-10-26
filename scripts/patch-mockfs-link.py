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
if [ -f "$ROOT/build/mockfs-fixture/libmockfs_fixture.a" ]; then
  MOCKFS_LINK="$ROOT/build/mockfs-fixture/libmockfs_fixture.a"
  FOUND_LD=0
  for i in "${!EXTRA_MAKE_ARGS[@]}"; do
    if [[ "${EXTRA_MAKE_ARGS[$i]}" == LD_KERNEL_ARCHIVES=* ]]; then
      EXTRA_MAKE_ARGS[$i]="${EXTRA_MAKE_ARGS[$i]} -Wl,-force_load,$MOCKFS_LINK"
      FOUND_LD=1
      break
    fi
  done
  if [ "$FOUND_LD" = 0 ]; then
    EXTRA_MAKE_ARGS+=("LD_KERNEL_ARCHIVES=-Wl,-force_load,$MOCKFS_LINK")
    EXTRA_MAKE_ARGS+=("XNU_EXTERNAL_KERNEL_ARCHIVES=$MOCKFS_LINK")
  fi
  echo "mockfs fixture linked: $MOCKFS_LINK"
fi'''

found = 0
for script in Path('.').rglob('build-xnu-4k-baseline.sh'):
    if '.git' in str(script):
        continue
    text = script.read_text()
    if 'mockfs fixture linked' in text:
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
