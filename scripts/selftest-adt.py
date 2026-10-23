#!/usr/bin/env python3
"""Self-test for make-enchilada-adt.py: generate a tree with the board.toml values,
then decode the Apple node encoding and assert the required structure."""
import struct
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
GEN = HERE / 'make-enchilada-adt.py'
OUT = HERE / 'selftest-adt.bin'

subprocess.check_call([sys.executable, str(GEN),
    '--output', str(OUT),
    '--dram-size', '0x180000000',
    '--owned-memory-size', '0x130000000',
    '--root-match-volume-uuid', '04769D26-2CA0-4825-B443-E2E5F88300F2',
    '--unique-chip-id', '3f2a9c11d4e6b807',
    '--chip-id', '208',
    '--ipad-identity',
    '--cpu-regs', '0,0x100,0x200,0x300,0x400,0x500,0x600,0x700',
    '--psci-method', 'smc',
    '--packed-data-ramdisk', '--persistent-data', '--trust-cache',
    '--text-fixup', 'dyld_shared_cache_arm64.15,421e8bc,28ad1bb0008544f9,c0035fd6008544f9'])

blob = OUT.read_bytes()

def parse(buf, off):
    nprops, nchildren = struct.unpack_from('<II', buf, off)
    off += 8
    props = {}
    for _ in range(nprops):
        key = buf[off:off+32].split(b'\0', 1)[0].decode()
        length = struct.unpack_from('<I', buf, off+32)[0]
        value = buf[off+36:off+36+length]
        props[key] = value
        off += 36 + length + (-length % 4)
    children = []
    for _ in range(nchildren):
        child, off = parse(buf, off)
        children.append(child)
    return (props, children), off

(root, end) = parse(blob, 0)
assert end == len(blob), f'trailing bytes: {end} != {len(blob)}'
props, children = root
assert props['name'] == b'device-tree\0'
assert props['model'] == b'iPad7,1\0'
assert props['target-type'] == b'J120\0'
names = [c[0]['name'].rstrip(b'\0').decode() for c in children]
print('root children:', names)
for required in ('chosen', 'cpus', 'psci', 'defaults', 'options', 'buttons', 'product', 'arm-io'):
    assert required in names, f'missing node {required}'
chosen = next(c for c in children if c[0]['name'] == b'chosen\0')
cp = chosen[0]
for key in ('random-seed', 'unique-chip-id', 'chip-id', 'osenvironment', 'dram-base', 'dram-size',
            'crypto-hash-method', 'root-matching', 'amfi-only-platform-code', 'text-fixups',
            'nvram-proxy-data', 'darwinboot-memory-size'):
    assert key in cp, f'missing /chosen/{key}'
assert len(cp['random-seed']) == 64
assert struct.unpack('<Q', cp['unique-chip-id'])[0] == 0x3f2a9c11d4e6b807
assert b'04769D26-2CA0-4825-B443-E2E5F88300F2' in cp['root-matching']
assert b'ephemeral-storage' not in cp, 'persistent data must not mark ephemeral-storage'
mm = next(c for c in chosen[1] if c[0]['name'] == b'memory-map\0')
mm_names = list(mm[0].keys())
assert 'PackedRAMDisk' in mm[0] and 'TrustCache' in mm[0], mm_names
assert len(mm[0]['PackedRAMDisk']) == 16 and len(mm[0]['TrustCache']) == 16
cpus = next(c for c in children if c[0]['name'] == b'cpus\0')
assert len(cpus[1]) == 8
comps = [c[0]['compatible'] for c in cpus[1]]
assert comps[0] == b'arm,cortex-a75\0' and comps[4] == b'arm,cortex-a55\0', comps
intc = next(c for c in next(c for c in children if c[0]['name'] == b'arm-io\0')[1]
            if c[0]['name'] == b'intc\0')
gic = struct.unpack('<4Q', intc[0]['reg'])
assert gic[0] == 0x17a00000 - 0x17000000 and gic[2] == 0x17a60000 - 0x17000000, gic
assert gic[1] == 0x10000 and gic[3] == 0x100000, gic
print(f'OK: {len(blob)} bytes, 8 cpus, GIC offsets {gic[0]:#x}/{gic[2]:#x}, /chosen keys {len(cp)}')
