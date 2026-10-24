"""Pack the C64's flash store for a Pico (src/pico_store.pmi has the format):
the ROMs, .PRG programs and .D64 disks, into one file for the C64's region
($1F0000, 60 KB, on the Pico W).

  py -3 tools/c64_store.py --roms <folder> [--prg game.prg ...] [--d64 disk.d64 ...] -o build/c64-store.bin

A .D64 is stored SPARSE ("D64S": the 683-entry sector map, then only the
sectors that are not all zeros), so a disk with one game on it fits. Nothing
this writes goes in git: the ROMs and most programs are copyrighted.
Write it to the board with tools/store_write.ps1 (holds the board's lease).
"""
import argparse, struct, sys
from pathlib import Path

REGION = 0xF000
TYPES = {'basic': 1, 'kernal': 2, 'chargen': 3, 'prg': 4, 'd64': 5}

def find_roms(folder):
    found = {}
    for p in sorted(Path(folder).iterdir()):
        if not p.is_file(): continue
        n, size = p.name.lower(), p.stat().st_size
        if size == 8192 and 'basic' in n: found['basic'] = p
        elif size == 8192 and 'kernal' in n: found['kernal'] = p
        elif size == 4096 and ('char' in n or '901225' in n): found['chargen'] = p
    missing = [k for k in ('basic', 'kernal', 'chargen') if k not in found]
    if missing:
        sys.exit(f'{folder}: no {", ".join(missing)} ROM (8192-byte basic*/kernal*, 4096-byte char*)')
    return found

def sparse_d64(data):
    if len(data) < 174848:
        sys.exit(f'not a 35-track .D64 ({len(data)} bytes)')
    data = data[:174848]
    smap, stored = [], []
    for i in range(683):
        sec = data[i * 256:(i + 1) * 256]
        if any(sec):
            smap.append(len(stored)); stored.append(sec)
        else:
            smap.append(0xFFFF)
    return b'D64S' + struct.pack('<683H', *smap) + b''.join(stored)

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--roms')
    ap.add_argument('--prg', action='append', default=[])
    ap.add_argument('--d64', action='append', default=[])
    ap.add_argument('-o', '--output', required=True)
    a = ap.parse_args()
    items = []
    if a.roms:
        for k, p in find_roms(a.roms).items():
            items.append((TYPES[k], k, p.read_bytes()))
    for p in a.prg:
        items.append((4, Path(p).stem, Path(p).read_bytes()))
    for p in a.d64:
        items.append((5, Path(p).stem, sparse_d64(Path(p).read_bytes())))
    head = 8 + 24 * len(items)
    off = (head + 3) & ~3
    entries, blob = b'', b''
    for kind, name, data in items:
        pos = off + len(blob)
        entries += struct.pack('<BBHII12s', kind, 0, 0, len(data), pos, name.encode('ascii', 'replace')[:12])
        blob += data + bytes((-len(data)) % 4)
    out = b'C64S' + struct.pack('<HH', len(items), 0) + entries
    out += bytes(off - len(out)) + blob
    if len(out) > REGION:
        sys.exit(f'store is {len(out)} bytes, the region holds {REGION}: leave something out')
    out += bytes((-len(out)) % 4096)
    Path(a.output).parent.mkdir(parents=True, exist_ok=True)
    Path(a.output).write_bytes(out)
    for kind, name, data in items:
        print(f'  {name:12s} type {kind}  {len(data)} bytes')
    print(f'{a.output}: {len(out)} bytes of {REGION}')

if __name__ == '__main__':
    main()
