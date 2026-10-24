"""Write a 35-track .D64 holding the given .PRG files, laid out as a 1541 would:
BAM and directory on track 18, files from track 17 outwards with sector interleave 10.

  py -3 tools/make_d64.py -o tests/pmdisk.d64 --name "PUREMETAL DISK" --id PM tests/demo.prg tests/modes.prg ...

(The test disk built from this project's own programs, so a disk can be tried without
anyone's copyrighted software.)
"""
import argparse
from pathlib import Path

SECTORS = [21] * 17 + [19] * 7 + [18] * 6 + [17] * 5

def offset(t, s):
    return (sum(SECTORS[:t - 1]) + s) * 256

def petscii(name):
    return name.upper().encode('ascii', 'replace')

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('-o', '--output', required=True)
    ap.add_argument('--name', default='PUREMETAL')
    ap.add_argument('--id', default='PM')
    ap.add_argument('files', nargs='+')
    a = ap.parse_args()
    img = bytearray(174848)
    used = {t: set() for t in range(1, 36)}
    used[18].update({0, 1})
    # tracks in the 1541's order: 17, 19, 16, 20, ...
    order = []
    for d in range(1, 18):
        for t in (18 - d, 18 + d):
            if 1 <= t <= 35: order.append(t)
    dirents = []
    for path in a.files:
        data = Path(path).read_bytes()
        chunks = [data[i:i + 254] for i in range(0, len(data), 254)] or [b'']
        blocks = []
        t_i, s = 0, 0
        for _ in chunks:
            while True:
                t = order[t_i]
                free = [x for x in range(SECTORS[t - 1]) if x not in used[t]]
                if free:
                    # interleave 10 from the last sector used on this track
                    cand = [(s + k * 1) % SECTORS[t - 1] for k in range(SECTORS[t - 1])]
                    s = next(x for x in cand if x not in used[t])
                    used[t].add(s); blocks.append((t, s)); s = (s + 10) % SECTORS[t - 1]
                    break
                t_i += 1; s = 0
        for i, (t, s) in enumerate(blocks):
            o = offset(t, s); chunk = chunks[i]
            if i + 1 < len(blocks):
                img[o], img[o + 1] = blocks[i + 1]
            else:
                img[o], img[o + 1] = 0, len(chunk) + 1
            img[o + 2:o + 2 + len(chunk)] = chunk
        name = petscii(Path(path).stem)[:16]
        dirents.append((name, blocks[0], len(blocks)))
    # directory: track 18 sector 1 (8 entries a sector, interleave 3)
    dsec = [1]
    while len(dsec) * 8 < len(dirents):
        nxt = (dsec[-1] + 3) % 19
        while nxt in used[18] or nxt in dsec: nxt = (nxt + 1) % 19
        dsec.append(nxt)
    for s in dsec: used[18].add(s)
    for k, s in enumerate(dsec):
        o = offset(18, s)
        if k + 1 < len(dsec): img[o], img[o + 1] = 18, dsec[k + 1]
        else: img[o], img[o + 1] = 0, 255
        for j, (name, (t, ss), n) in enumerate(dirents[k * 8:k * 8 + 8]):
            e = o + j * 32
            img[e + 2] = 0x82
            img[e + 3], img[e + 4] = t, ss
            img[e + 5:e + 21] = name.ljust(16, b'\xa0')
            img[e + 30], img[e + 31] = n & 255, n >> 8
    # BAM
    b = offset(18, 0)
    img[b], img[b + 1], img[b + 2] = 18, 1, 0x41
    for t in range(1, 36):
        free = [x for x in range(SECTORS[t - 1]) if x not in used[t]]
        bits = sum(1 << x for x in free)
        img[b + 4 * t:b + 4 * t + 4] = bytes([len(free), bits & 255, (bits >> 8) & 255, (bits >> 16) & 255])
    img[b + 0x90:b + 0xA0] = petscii(a.name)[:16].ljust(16, b'\xa0')
    img[b + 0xA0:b + 0xA2] = b'\xa0\xa0'
    img[b + 0xA2:b + 0xA4] = petscii(a.id)[:2].ljust(2, b'\xa0')
    img[b + 0xA4] = 0xA0
    img[b + 0xA5:b + 0xA7] = b'2A'
    img[b + 0xA7:b + 0xAB] = b'\xa0' * 4
    Path(a.output).write_bytes(img)
    print(a.output, len(dirents), 'files', sum(n for _, _, n in dirents), 'blocks')

if __name__ == '__main__':
    main()
