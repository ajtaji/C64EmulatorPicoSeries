"""Build the built-in demo: a C64 program written here (no ROM code), so the
machine's video, raster interrupt, sprites and SID can be shown on a screen
before any ROM is present. It runs with the ROMs banked out ($01 = $35).

What it shows: "PUREMETAL C64" in a font of its own, raster-split colour bars
in the border (a VIC raster IRQ at several lines), a Y-expanded sprite moving
across, and a short SID tune (pulse voice with a filter sweep, triangle bass).

Writes tests/demo.prg and src/demo_data.pmi (a DataSection, DemoPrg).
Assembled with py65's assembler, two passes for the labels.
"""
from pathlib import Path
import re
from py65.assembler import Assembler
from py65.devices.mpu6502 import MPU

ROOT = Path(__file__).resolve().parent.parent
ORG = 0xC000

SRC = r'''
start:  SEI
        CLD
        LDX #$FF
        TXS
        LDA #$35
        STA $01
        LDA #$7F
        STA $DC0D
        STA $DD0D
        LDA $DC0D
        LDA $DD0D
        LDA #$03
        STA $DD02
        STA $DD00
        LDA #<irq
        STA $FFFE
        LDA #>irq
        STA $FFFF
        LDA #<nmi
        STA $FFFA
        LDA #>nmi
        STA $FFFB
; the font: glyph n at $3000 + n*8
        LDX #0
font:   LDA glyphs,X
        STA $3000,X
        INX
        CPX #glyphs_len
        BNE font
; clear the screen (glyph 0 = space) and colour RAM
        LDX #0
clr:    LDA #0
        STA $0400,X
        STA $0500,X
        STA $0600,X
        STA $06E8,X
        LDA #14
        STA $D800,X
        STA $D900,X
        STA $DA00,X
        STA $DAE8,X
        INX
        BNE clr
; the text, twice, in two colours
        LDX #0
txt:    LDA text,X
        STA $0400+40*10+13,X
        STA $0400+40*14+13,X
        LDA #1
        STA $D800+40*10+13,X
        LDA #7
        STA $D800+40*14+13,X
        INX
        CPX #13
        BNE txt
; the sprite: 21 rows at $2000 (pointer $80)
        LDX #0
spr:    LDA sprite,X
        STA $2000,X
        INX
        CPX #63
        BNE spr
        LDA #$80
        STA $07F8
        LDA #$01
        STA $D015
        STA $D017
        LDA #10
        STA $D027
        LDA #100
        STA $D001
        LDA #24
        STA $D000
; the screen at $0400, characters at $3000
        LDA #$1C
        STA $D018
        LDA #$1B
        STA $D011
        LDA #$08
        STA $D016
        LDA #6
        STA $D020
        STA $D021
; the raster IRQ, first at line 40
        LDA #40
        STA $D012
        LDA #$01
        STA $D01A
        STA $D019
; the SID
        LDA #$0F
        STA $D418
        LDA #$09
        STA $D405
        LDA #$A8
        STA $D406
        LDA #$00
        STA $D402
        LDA #$08
        STA $D403
        LDA #$24
        STA $D40C
        LDA #$80
        STA $D40D
        LDA #$11
        STA $D417
        LDA #$1F
        STA $D418
        LDA #0
        STA frame
        STA step
        CLI
main:   JMP main

nmi:    RTI

irq:    PHA
        TXA
        PHA
        TYA
        PHA
        LDA #$FF
        STA $D019
        LDX bar
        LDA barcol,X
        STA $D020
        INX
        CPX #8
        BNE irq2
        LDX #0
        JSR perframe
irq2:   STX bar
        LDA barline,X
        STA $D012
        PLA
        TAY
        PLA
        TAX
        PLA
        RTI

perframe:
        INC frame
        INC $D000
        BNE pf1
        LDA $D010
        EOR #1
        STA $D010
pf1:    LDA frame
        AND #$03
        BNE pf2
        INC cut
        LDA cut
        STA $D416
pf2:    LDA frame
        AND #$0F
        BNE pfend
        LDA #$40
        STA $D404
        LDA #$10
        STA $D40B
        LDY step
        LDA tunelo,Y
        STA $D400
        LDA tunehi,Y
        STA $D401
        LDA basslo,Y
        STA $D407
        LDA basshi,Y
        STA $D408
        LDA #$41
        STA $D404
        LDA #$11
        STA $D40B
        INY
        TYA
        AND #$07
        STA step
pfend:  RTS

frame:  .byte 0
step:   .byte 0
bar:    .byte 0
cut:    .byte 0
barline: .byte 30, 38, 46, 54, 236, 244, 252, 255
barcol:  .byte 2, 8, 7, 5, 14, 4, 6, 6
tunelo:  .byte $25, $9A, $4B, $3A, $9A, $4B, $25, $34
tunehi:  .byte $11, $15, $19, $1A, $15, $19, $11, $1D
basslo:  .byte $49, $49, $C3, $C3, $49, $49, $87, $87
basshi:  .byte $04, $04, $05, $05, $04, $04, $03, $03
text:    .byte 1, 2, 3, 4, 5, 4, 6, 7, 8, 0, 9, 10, 11
sprite:
'''

# 8x8 glyphs: space P U R E M T A L C 6 4
GLYPHS = {
    ' ': '........ ........ ........ ........ ........ ........ ........ ........',
    'P': '######.. ##...##. ##...##. ######.. ##...... ##...... ##...... ........',
    'U': '##...##. ##...##. ##...##. ##...##. ##...##. ##...##. .#####.. ........',
    'R': '######.. ##...##. ##...##. ######.. ##.##... ##..##.. ##...##. ........',
    'E': '#######. ##...... ##...... #####... ##...... ##...... #######. ........',
    'M': '##...##. ###.###. #######. ##.#.##. ##...##. ##...##. ##...##. ........',
    'T': '######.. ..##.... ..##.... ..##.... ..##.... ..##.... ..##.... ........',
    'A': '..###... .##.##.. ##...##. #######. ##...##. ##...##. ##...##. ........',
    'L': '##...... ##...... ##...... ##...... ##...... ##...... #######. ........',
    'C': '.#####.. ##...##. ##...... ##...... ##...... ##...##. .#####.. ........',
    '6': '..####.. .##..... ##...... ######.. ##...##. ##...##. .#####.. ........',
    '4': '....##.. ...###.. ..####.. .##.##.. #######. ....##.. ....##.. ........',
}
ORDER = ' PUREMTALC64'
SPRITE = ['.........######.........', '.......##########.......', '.....##############.....',
          '....################....', '...######..##..######...', '..#######..##..#######..',
          '..####################..', '.######################.', '.######################.',
          '.######################.', '.######################.', '.#####.############.###.',
          '..#####.##########.###..', '..######..######..####..', '...######........####...',
          '....######################'[:24], '.....##############.....', '.......##########.......',
          '.........######.........', '........................', '........................']

def glyph_bytes():
    out = []
    for ch in ORDER:
        for row in GLYPHS[ch].split():
            out.append(int(row.replace('#', '1').replace('.', '0'), 2))
    return out

def sprite_bytes():
    out = []
    for row in SPRITE:
        row = row.ljust(24, '.')[:24]
        bits = int(row.replace('#', '1').replace('.', '0'), 2)
        out += [(bits >> 16) & 255, (bits >> 8) & 255, bits & 255]
    return out

def assemble(src):
    asm = Assembler(MPU())
    lines = []
    for raw in src.splitlines():
        line = raw.split(';')[0].rstrip()
        if not line.strip():
            continue
        label = None
        m = re.match(r'^(\w+):\s*(.*)$', line.strip())
        if m:
            label, line = m[1], m[2]
        lines.append((label, line.strip()))
    extra = {'glyphs_len': len(glyph_bytes())}
    labels = {}
    for npass in range(3):
        pc = ORG; out = []
        for label, text in lines:
            if label:
                labels[label] = pc
            if not text:
                continue
            if text.startswith('.byte'):
                vals = [int(v.strip().replace('$', '0x'), 0) for v in text[5:].split(',')]
                out += vals; pc += len(vals); continue
            def sub(m):
                name = m[2]; v = labels.get(name, extra.get(name, 0x1234 if npass == 0 else None))
                if v is None:
                    raise SystemExit(f'unknown label {name}')
                if m[1] == '<': return f'${v & 255:02X}'
                if m[1] == '>': return f'${v >> 8:02X}'
                return f'${v:04X}' if name not in extra else f'${v:02X}'
            t = re.sub(r'([<>]?)\b([a-z_][a-z0-9_]*)\b', sub, text)
            # arithmetic in operands ($0400+40*10+13)
            t = re.sub(r'\$([0-9A-F]+)((?:[+*]\d+)+)', lambda m: f'${eval(str(int(m[1],16))+m[2]):04X}', t)
            # py65 reads bare numbers as hex: decimal immediates become $xx
            t = re.sub(r'#(\d+)\b', lambda m: f'#${int(m[1]):02X}', t)
            try:
                code = asm.assemble(t, pc)
            except OverflowError:
                raise SystemExit(f"overflow: {t!r} at {pc:04X} pass {npass}")
            if code is None:
                raise SystemExit(f'cannot assemble: {t}')
            out += code; pc += len(code)
        labels['glyphs'] = pc + 63
    data = out + sprite_bytes() + glyph_bytes()
    labels['glyphs'] = ORG + len(out) + 63
    return data, labels

def main():
    data, labels = assemble(SRC)
    prg = bytes([ORG & 255, ORG >> 8]) + bytes(data)
    (ROOT / 'tests' / 'demo.prg').write_bytes(prg)
    lines = ['; GENERATED by tools/make_demo.py - the built-in demo (a program of this project, no ROM code).',
             '#DEMO_START = $C000', f'#DEMO_SIZE = {len(prg)}', 'DataSection', 'DemoPrg:']
    for i in range(0, len(prg), 32):
        lines.append('  Data.a ' + ','.join(f'${b:02X}' for b in prg[i:i + 32]))
    lines.append('EndDataSection')
    (ROOT / 'src' / 'demo_data.pmi').write_text('\n'.join(lines) + '\n', newline='\n')
    print('demo:', len(prg), 'bytes; glyphs at', hex(labels['glyphs']))

if __name__ == '__main__':
    main()
