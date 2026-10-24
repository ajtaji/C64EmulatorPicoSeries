"""tests/modes.prg: every VIC-II graphics mode on one screen, for checking a renderer
change pixel for pixel. A raster IRQ switches mode and X scroll in bands:
  text, multicolour text, extended-colour text, bitmap, multicolour bitmap, an invalid
  mode, then text again with 38 columns; each band with a different X scroll.
Screen $0400 (characters: a pattern of codes 0-255), font copied from nothing: the
character "ROM" is RAM at $2000 filled with a computed pattern; bitmap at $2000 too
(the same bytes serve both). Two sprites (one multicolour, expanded) cross the bands.
Built with tools/make_demo.py's assembler."""
from pathlib import Path
import importlib.util, sys
ROOT = Path(__file__).resolve().parent.parent
spec = importlib.util.spec_from_file_location('md', ROOT / 'tools' / 'make_demo.py')
md = importlib.util.module_from_spec(spec); spec.loader.exec_module(md)
SRC = r'''
start:  SEI
        LDX #$FF
        TXS
        LDA #$35
        STA $01
        LDA #$7F
        STA $DC0D
        LDA $DC0D
        LDA #$03
        STA $DD02
        STA $DD00
        LDA #<irq
        STA $FFFE
        LDA #>irq
        STA $FFFF
; pattern memory $2000-$3FFF: byte = (addr * 37) xor (addr >> 5)
        LDA #$00
        STA $FB
        LDA #$20
        STA $FC
        LDY #0
fill:   TYA
        CLC
        ADC $FC
        EOR $FB
        ASL A
        ADC $FB
        STA ($FB),Y
        INY
        BNE fill
        INC $FC
        LDA $FC
        CMP #$40
        BNE fill
; screen codes 0..255 repeating, colours 0..15 repeating
        LDX #0
scr:    TXA
        STA $0400,X
        STA $0500,X
        STA $0600,X
        STA $06E8,X
        STA $D800,X
        STA $D900,X
        STA $DA00,X
        STA $DAE8,X
        INX
        BNE scr
; sprites: data at $0E00 / $0E40
        LDX #0
spr:    TXA
        EOR #$5A
        STA $0E00,X
        INX
        CPX #128
        BNE spr
        LDA #$38
        STA $07F8
        LDA #$39
        STA $07F9
        LDA #$03
        STA $D015
        LDA #$02
        STA $D01C
        STA $D01D
        STA $D017
        LDA #7
        STA $D027
        LDA #10
        STA $D028
        LDA #12
        STA $D025
        LDA #13
        STA $D026
        LDA #60
        STA $D000
        LDA #70
        STA $D001
        LDA #150
        STA $D002
        LDA #120
        STA $D003
        LDA #$18
        STA $D018
        LDA #2
        STA $D020
        LDA #6
        STA $D021
        LDA #3
        STA $D022
        LDA #4
        STA $D023
        LDA #5
        STA $D024
        LDA #0
        STA band
        LDA #40
        STA $D012
        LDA #$1B
        STA $D011
        LDA #$01
        STA $D01A
        STA $D019
        CLI
main:   JMP main

irq:    PHA
        TXA
        PHA
        LDA #$FF
        STA $D019
        LDX band
        LDA d011,X
        STA $D011
        LDA d016,X
        STA $D016
        INX
        CPX #8
        BNE irq2
        LDX #0
irq2:   STX band
        LDA line,X
        STA $D012
        PLA
        TAX
        PLA
        RTI

band:   .byte 0
line:   .byte 40, 72, 96, 120, 144, 168, 192, 216
d011:   .byte $1B, $1B, $5B, $3B, $3B, $7B, $1B, $1B
d016:   .byte $08, $19, $0A, $0B, $1C, $0D, $06, $0F
'''
def main():
    data, labels = md.assemble(SRC)
    prg = bytes([md.ORG & 255, md.ORG >> 8]) + bytes(data)
    (ROOT / 'tests' / 'modes.prg').write_bytes(prg)
    print('modes:', len(prg), 'bytes')
main()
