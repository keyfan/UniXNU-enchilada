#!/usr/bin/env python3
"""Build minimal PMGR stub for enchilada. Provides _sheng_pmgr_run for linking."""
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'build/sheng-platform-power'
OUT.mkdir(parents=True, exist_ok=True)

source = ROOT / 'kits/enchilada-pmgr/ShengPlatformPower.cpp'
obj = OUT / 'ShengPlatformPower.o'
archive = OUT / 'libShengPlatformPower.a'

# Compile with generic ARM64/iOS17 flags
sdk = subprocess.check_output(
    ['xcrun', '--sdk', 'iphoneos', '--show-sdk-path'], text=True
).strip()

cmd = [
    'xcrun', 'clang',
    '-target', 'arm64-apple-ios17.0',
    '-isysroot', sdk,
    '-c', str(source),
    '-o', str(obj),
    '-O2', '-Wall', '-Wextra', '-Wno-unused-parameter',
]
print(f'Compiling: {" ".join(cmd)}')
subprocess.check_call(cmd)

# Create archive
archive.unlink(missing_ok=True)
subprocess.check_call(['xcrun', 'ar', 'rcs', str(archive), str(obj)])
print(f'PASS: created {archive} ({archive.stat().st_size} bytes)')
