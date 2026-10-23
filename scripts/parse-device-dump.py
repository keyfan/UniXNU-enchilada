#!/usr/bin/env python3
"""One-shot: parse backup/ (boot_a.img + gpt-sda.bin) from the OnePlus 6 and print
the values needed by UniXNU-enchilada (board.toml, uefi-enchilada config, ADT constants)."""
import struct
import sys
from pathlib import Path

BACKUP = Path(__file__).resolve().parents[2] / 'backup'


def parse_gpt(path):
    data = path.read_bytes()
    off = data.find(b'EFI PART')
    assert off >= 0, 'no GPT header'
    (sig, rev, hdr_size, hdr_crc, _res, current, backup_lba, first_usable,
     last_usable, disk_guid, entries_lba, num_entries, entry_size) = struct.unpack_from('<8sIIIIQQQQ16sQII', data, off)
    out = []
    eoff = off + hdr_size if entries_lba == 1 else off + (entries_lba * 512 - 0)  # entries follow header in sgdisk backup
    # sgdisk backup = GPT header (LBA1) then entries; locate entries right after 512-aligned header
    eoff = ((off + 512 + 511) // 512) * 512
    for i in range(num_entries):
        e = data[eoff + i * entry_size: eoff + (i + 1) * entry_size]
        if len(e) < entry_size:
            break
        type_guid = e[0:16]
        if type_guid == b'\x00' * 16:
            continue
        first, last, attrs = struct.unpack_from('<QQQ', e, 32)
        name = e[56:128].decode('utf-16-le', errors='replace').rstrip('\x00')
        if not name or not all(c.isprintable() for c in name):
            continue
        out.append((name, first, last, attrs))
    return out


def parse_boot(path):
    d = path.read_bytes()
    assert d[:8] == b'ANDROID!', 'not a boot image'
    (k_size, k_addr, r_size, r_addr, s_size, s_addr, tags_addr,
     page_size, hdr_ver_or_dt, os_ver) = struct.unpack_from('<10I', d, 8)
    name = d[48:64].split(b'\x00')[0].decode(errors='replace')
    cmdline = (d[64:576] + d[592:1616]).split(b'\x00')[0].decode(errors='replace')
    hdr_ver = hdr_ver_or_dt if hdr_ver_or_dt in (0, 1, 2, 3, 4) else 0
    return dict(magic='ANDROID!', kernel_size=k_size, kernel_addr=k_addr, ramdisk_size=r_size,
                ramdisk_addr=r_addr, second_size=s_size, second_addr=s_addr, tags_addr=tags_addr,
                page_size=page_size, header_version=hdr_ver, os_version=os_ver, name=name,
                cmdline=cmdline[:200])


def parse_fdt(blob):
    (magic, total, off_struct, off_strings, _rsv, ver, last_comp, boot_cpuid,
     size_strings, size_struct) = struct.unpack_from('>10I', blob, 0)
    assert magic == 0xD00DFEED
    strings = blob[off_strings:off_strings + size_strings]
    pos = off_struct
    stack = []
    nodes = {}   # path -> {props}
    FDT_BEGIN, FDT_END, FDT_PROP, FDT_NOP, FDT_ENDN = 1, 2, 3, 4, 9
    while pos < off_struct + size_struct:
        token = struct.unpack_from('>I', blob, pos)[0]
        pos += 4
        if token == FDT_BEGIN:
            end = blob.index(b'\x00', pos)
            name = blob[pos:end].decode(errors='replace')
            pos = (end + 4) & ~3
            stack.append(name)
            nodes.setdefault('/'.join(stack) or '/', {})
        elif token == FDT_END:
            stack.pop()
        elif token == FDT_PROP:
            length, nameoff = struct.unpack_from('>II', blob, pos)
            pos += 8
            value = blob[pos:pos + length]
            pos = (pos + length + 3) & ~3
            pname = strings[nameoff:strings.index(b'\x00', nameoff)].decode(errors='replace')
            path = '/'.join(stack) or '/'
            nodes.setdefault(path, {})[pname] = value
        elif token == FDT_NOP:
            continue
        elif token == FDT_ENDN:
            break
    return nodes


def fmt_reg(v):
    cells = struct.unpack('>%dI' % (len(v) // 4), v)
    if len(cells) == 2:
        return f'{(cells[0] << 32) | cells[1]:#x}'
    if len(cells) == 4:
        return f'{(cells[0] << 32) | cells[1]:#x} size {(cells[2] << 32) | cells[3]:#x}'
    return ' | '.join(f'{(cells[i] << 32) | cells[i+1]:#x} size {(cells[i+2] << 32) | cells[i+3]:#x}'
                      for i in range(0, len(cells) - 3, 4)) or repr(cells)


def main():
    print('== GPT (gpt-sda.bin) ==')
    for name, first, last, attrs in parse_gpt(BACKUP / 'gpt-sda.bin'):
        mark = ' <== userdata' if name == 'userdata' else ''
        print(f'  {name:12s} first_lba={first:#x} ({first})  last_lba={last:#x} ({last}){mark}')

    print('\n== boot image header (boot_a.img) ==')
    hdr = parse_boot(BACKUP / 'boot_a.img')
    for k, v in hdr.items():
        print(f'  {k}: {v}')

    print('\n== FDT constants (dtb inside boot_a.img) ==')
    blob = (BACKUP / 'boot_a.img').read_bytes()
    idx = blob.find(b'\xd0\x0d\xfe\xed')
    dtbs = []
    while idx != -1:
        try:
            total = struct.unpack_from('>I', blob, idx + 4)[0]
            if 64 < total < 4_000_000:
                dtbs.append((idx, blob[idx:idx + total]))
        except struct.error:
            pass
        idx = blob.find(b'\xd0\x0d\xfe\xed', idx + 4)
    print(f'  found {len(dtbs)} FDT blob(s) at {[hex(i) for i, _ in dtbs]}')
    nodes = parse_fdt(dtbs[0][1])
    for path, props in sorted(nodes.items()):
        if path.startswith('/cpus/') or path == '/cpus':
            for k in ('device_type', 'compatible', 'reg'):
                if k in props:
                    v = props[k]
                    if k == 'reg':
                        print(f'  {path} reg={fmt_reg(v)}')
                    else:
                        print(f'  {path} {k}={v.rstrip(chr(0).encode()).decode(errors="replace")}')
        if 'interrupt-controller' in path or 'gic' in str(props.get('compatible', b'')):
            if 'reg' in props:
                print(f'  {path} compatible={props.get("compatible", b"").rstrip(chr(0).encode()).decode(errors="replace")} reg={fmt_reg(props["reg"])}')
            if 'redistributor-stride' in props or 'redistributor_region_stride' in props:
                key = 'redistributor-stride' if 'redistributor-stride' in props else 'redistributor_region_stride'
                print(f'  {path} {key}={struct.unpack(">Q", props[key])[0]:#x}' if len(props[key]) == 8 else f'  {path} {key}={props[key].hex()}')
        if 'splash' in path or 'splash' in str(props.get('label', b'')):
            print(f'  {path} label={props.get("label", b"").rstrip(chr(0).encode())} reg={fmt_reg(props["reg"]) if "reg" in props else None}')
        if 'ufshc' in path or 'ufshci' in path or '1d84000' in path:
            print(f'  {path} compatible={props.get("compatible", b"").rstrip(chr(0).encode()).decode(errors="replace")} reg={fmt_reg(props["reg"]) if "reg" in props else None}')
    cpu_regs = []
    for path, props in sorted(nodes.items()):
        if path.startswith('/cpus/') and 'reg' in props:
            cells = struct.unpack('>%dI' % (len(props['reg']) // 4), props['reg'])
            if len(cells) == 1:
                cpu_regs.append(cells[0])
            elif len(cells) == 2:
                cpu_regs.append((cells[0] << 32) | cells[1])
    print(f'  /cpus MPIDR list: {[hex(r) for r in sorted(cpu_regs)]}')
    root_compat = nodes.get('/', {}).get('compatible', b'')
    print('  root compatible:', root_compat.replace(bytes([0]), b' ').decode(errors='replace'))


if __name__ == '__main__':
    main()
