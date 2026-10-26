#!/usr/bin/env python3
"""Patch build-xnu-4k-baseline.sh to always link the mockfs fixture.

The archive-linking section is gated by `if [ CORECRYPTO=1 ] && [ BOOTSTRAP=0 ]`.
During the first pass (BOOTSTRAP=1), archives aren't built yet so the gate is
correct. But during the final pass (BOOTSTRAP=0), the mockfs fixture must be
linked. This script adds the mockfs linking OUTSIDE the gate so it works
regardless of BOOTSTRAP mode.
"""
import sys
from pathlib import Path

script = Path('scripts/build-xnu-4k-baseline.sh')
text = script.read_text()

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

if needle in text:
    text = text.replace(needle, insert, 1)
    script.write_text(text)
    print("PATCHED OK: mockfs linking added outside BOOTSTRAP gate")
else:
    if 'mockfs fixture linked' in text:
        print("Already patched")
    else:
        print("PATTERN NOT FOUND")
        sys.exit(1)
