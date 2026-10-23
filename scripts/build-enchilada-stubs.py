#!/usr/bin/env python3
"""Build the enchilada bring-up stubs.

The offline-component-load-probes xnu patch calls native_legacy_display_probe()
unconditionally; on sheng the display driver kit defines it. For the console
first bring-up a no-op definition is enough (the probe only matters once the
display pipeline is ported). The archive is linked through
CONFIG_XNU_EXTRA_LD_ARCHIVES.
"""
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[1]
out = ROOT / 'build/enchilada-stubs'
out.mkdir(parents=True, exist_ok=True)
source = out / 'enchilada-stubs.c'
source.write_text(
    '/* Bring-up stubs for the enchilada console kernel. */\n'
    'void native_legacy_display_probe(void);\n'
    'void native_legacy_display_probe(void) { }\n')
obj = out / 'enchilada-stubs.o'
subprocess.run(['xcrun', 'clang', '-target', 'arm64-apple-ios17.0', '-O2',
                '-Werror', '-c', str(source), '-o', str(obj)], check=True)
archive = out / 'libEnchiladaStubs.a'
archive.unlink(missing_ok=True)
subprocess.run(['xcrun', 'ar', 'rcs', str(archive), str(obj)], check=True)
print(f'enchilada stubs: {archive}')
