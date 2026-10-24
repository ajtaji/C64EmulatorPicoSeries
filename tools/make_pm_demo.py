"""Writes demo/c64demo.c64: the PureMetal C64 demo (music + graphics). Only the tables are generated
here (screen codes, SID frequencies, the song, the sprite); the program text is below as written."""
import math, os
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

def scr(text):            # PETSCII upper case -> screen codes
    out = []
    for ch in text.upper():
        o = ord(ch)
        if 64 <= o <= 95: out.append(o - 64)
        elif 32 <= o <= 63: out.append(o)
        else: out.append(32)
    return out

def rows(name, vals, kind='a', per=16):
    s = '  ' + name + ':\n'
    for i in range(0, len(vals), per):
        s += '  Data.' + kind + ' ' + ', '.join(str(v) for v in vals[i:i + per]) + '\n'
    return s

# SID frequency (PAL, 985248 Hz) of note n = semitones from C-0
freq = [min(65535, round(16.3516 * 2 ** (n / 12) * 16777216 / 985248)) for n in range(96)]
def N(name):
    names = {'C': 0, 'C#': 1, 'D': 2, 'D#': 3, 'E': 4, 'F': 5, 'F#': 6, 'G': 7, 'G#': 8, 'A': 9, 'A#': 10, 'B': 11}
    return names[name[:-1]] + 12 * int(name[-1])

# 4 bars of 8 steps: Am  F  C  G
roots = ['A2', 'F2', 'C3', 'G2']
chords = {'A2': (0, 3, 7), 'F2': (0, 4, 7), 'C3': (0, 4, 7), 'G2': (0, 4, 7)}
bass, arp0, arp1, arp2 = [], [], [], []
for r in roots:
    b = N(r)
    for s in range(8):
        bass.append(b if s in (0, 3, 4, 6) else (b + 12 if s == 7 else 0))
    c = chords[r]
    arp0.append(b + 24 + c[0]); arp1.append(b + 24 + c[1]); arp2.append(b + 24 + c[2])
lead_txt = ('E5 0 C5 0 A4 0 C5 E5 F5 0 E5 0 C5 0 A4 0 '
            'G4 0 C5 0 E5 0 G5 0 G5 0 F5 0 D5 0 B4 0').split()
lead = [N(x) if x != '0' else 0 for x in lead_txt]

ball = []
for y in range(21):
    bits = 0
    for x in range(24):
        dx, dy = x - 11.5, y - 10
        if dx * dx + dy * dy <= 10.5 * 10.5: bits |= 1 << (23 - x)
    ball += [(bits >> 16) & 255, (bits >> 8) & 255, bits & 255]

bars = [0, 6, 14, 3, 1, 3, 14, 6, 0, 2, 10, 7, 1, 7, 10, 2]
title = scr('    PUREMETAL FORGE  -  COMMODORE 64    ')
sub = scr('  WRITTEN IN PUREMETAL, BUILT BY PMFORGE ')
msg = scr('HELLO FROM PUREMETAL!  THREE SID VOICES, RASTER BARS, A BOUNCING SPRITE AND '
          'THIS SMOOTH SCROLLER - ALL WRITTEN IN PUREMETAL AND COMPILED FOR THE C64 ...     ')
grad = [11, 12, 15, 1, 1, 15, 12, 11]

src = open(os.path.join(ROOT, 'tools', 'pm_demo_body.c64')).read()
data = '\nDataSection\n'
data += rows('freqlo', [f & 255 for f in freq]) + rows('freqhi', [f >> 8 for f in freq])
data += rows('bass', bass) + rows('lead', lead)
data += rows('arp0', arp0) + rows('arp1', arp1) + rows('arp2', arp2)
data += rows('bars', bars) + rows('grad', grad)
data += rows('ball', ball, per=21)
data += rows('title', title, per=20) + rows('sub', sub, per=20)
data += rows('msg', msg + [255], per=20)
data += 'EndDataSection\n'
open(os.path.join(ROOT, 'demo', 'c64demo.c64'), 'w', newline='\n').write(src + data)
print('demo/c64demo.c64', len(msg), 'scroller characters')
