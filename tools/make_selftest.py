"""tests/selftest.prg: the machine checking itself, with no KERNAL code.

`10 SYS 2061` at $0801 and the code at $080D, so it RUNs from BASIC on a C64 (or this emulator with
ROMs) and starts at $080D without any (c64_check --demo --prg). It masks interrupts, banks the ROMs out
($01 = $35), points the 6510's own vectors at its handlers and checks, one line each on the screen:

  PLA       RAM under BASIC / KERNAL / character ROM, writes through ROM, I/O at $D000
  KEYBOARD  no key down: the matrix reads $FF with every column driven
  TIMER     CIA 1 timer A one-shot: the underflow flag after 512 cycles (+-15%), the timer stops, the
            ICR read clears the flag; continuous mode counts
  TOD       CIA 1 time of day (50 Hz): 20 frames are 3 or 4 tenths
  RASTER    a raster IRQ at line 100: one a frame, taken on line 100 or 101
  SPRITES   sprite-sprite collision of sprites 0 and 1 only; sprite 2 on text: sprite-background
  BADLINE   a badline leaves the CPU 23 of 63 cycles: a polling loop runs fewer times on line 91
  SID       voice 3's noise on OSC3 changes; ENV3 rises with the gate (attack 2 ms) and falls after
  NMI       CIA 2 timer A one-shot, NMI enabled: one NMI, its ICR shows the timer

then ALL TESTS PASSED (green border) or N TESTS FAILED (red). $02 = failures, $03 = $AA when done.
A FAIL shows a code: which check inside the test failed (see the source below).
"""
from pathlib import Path
import importlib.util
ROOT = Path(__file__).resolve().parent.parent
spec = importlib.util.spec_from_file_location('md', ROOT / 'tools' / 'make_demo.py')
md = importlib.util.module_from_spec(spec); spec.loader.exec_module(md)

def scr(text):
    out = []
    for ch in text.upper():
        o = ord(ch)
        out.append(o - 64 if 64 <= o <= 95 else (o if 32 <= o <= 63 else 32))
    return out

TESTS = ['pla', 'keyboard', 'timer', 'tod', 'raster', 'sprites', 'badline', 'sid', 'nmi']

def row(r, col=0):
    return 0x0400 + r * 40 + col

def text_block(label, r, text):
    """Code that writes `text` at row r, and its .byte string."""
    code = f"""        LDX #0
{label}_l: LDA {label}_t,X
        BEQ {label}_e
        STA ${row(r):04X},X
        INX
        BNE {label}_l
{label}_e:
"""
    data = f"{label}_t: .byte " + ', '.join(str(v) for v in scr(text) + [0]) + "\n"
    return code, data

def main():
    md.ORG = 0x0801
    names, strings = '', ''
    c, d = text_block('title', 0, 'PUREMETAL C64 SELF TEST - NO KERNAL USED')
    names += c; strings += d
    calls = ''
    for i, t in enumerate(TESTS):
        c, d = text_block('n' + t, 2 + i, t.upper() + ' ' + '.' * (11 - len(t)))
        names += c; strings += d
        dest = row(2 + i, 13)
        calls += f"""        JSR t_{t}
        LDX #${dest & 255:02X}
        STX $FD
        LDX #${dest >> 8:02X}
        STX $FE
        JSR report
"""
    c_ok, d_ok = text_block('allok', 13, 'ALL TESTS PASSED')
    c_bad, d_bad = text_block('somebad', 13, '  TESTS FAILED')
    strings += d_ok + d_bad
    src = f"""
basic:  .byte $0B, $08, $0A, $00, $9E, $32, $30, $36, $31, $00, $00, $00
start:  SEI
        CLD
        LDX #$FF
        TXS
        LDA #$2F
        STA $00
        LDA #$35
        STA $01
        LDA #$7F
        STA $DC0D
        STA $DD0D
        LDA $DC0D
        LDA $DD0D
        LDA #0
        STA $D01A
        STA $D015
        STA $D418
        LDA #$FF
        STA $D019
        LDA #$1B
        STA $D011
        LDA #$C8
        STA $D016
        LDA #$14
        STA $D018
        LDA #$03
        STA $DD02
        STA $DD00
        LDA #0
        STA $D020
        LDA #6
        STA $D021
        LDA #<irq
        STA $FFFE
        LDA #>irq
        STA $FFFF
        LDA #<nmi
        STA $FFFA
        LDA #>nmi
        STA $FFFB
        LDX #0
cls:    LDA #32
        STA $0400,X
        STA $0500,X
        STA $0600,X
        STA $06E8,X
        LDA #1
        STA $D800,X
        STA $D900,X
        STA $DA00,X
        STA $DAE8,X
        INX
        BNE cls
        LDA #0
        STA $02
        STA $03
{names}
{calls}
        LDA $02
        BNE fails
{c_ok}
        LDA #5
        STA $D020
        JMP done
fails:  ORA #48
        STA ${row(13):04X}
{c_bad}
        LDA $02
        ORA #48
        STA ${row(13):04X}
        LDA #2
        STA $D020
done:   LDA #$AA
        STA $03
hang:   JMP hang

; A = 0: OK at ($FD); else FAIL and the code in hex, and one more failure counted
report: STA $04
        LDY #0
        CMP #0
        BNE rfail
        LDA #15
        STA ($FD),Y
        INY
        LDA #11
        STA ($FD),Y
        RTS
rfail:  INC $02
        LDA #6
        STA ($FD),Y
        INY
        LDA #1
        STA ($FD),Y
        INY
        LDA #9
        STA ($FD),Y
        INY
        LDA #12
        STA ($FD),Y
        INY
        INY
        LDA $04
        LSR A
        LSR A
        LSR A
        LSR A
        TAX
        LDA hexd,X
        STA ($FD),Y
        INY
        LDA $04
        AND #15
        TAX
        LDA hexd,X
        STA ($FD),Y
        RTS
hexd:   .byte 48, 49, 50, 51, 52, 53, 54, 55, 56, 57, 1, 2, 3, 4, 5, 6

; X frames: each ends when the raster leaves line 250
frames: LDA $D012
        CMP #250
        BNE frames
fr2:    LDA $D012
        CMP #250
        BEQ fr2
        DEX
        BNE frames
        RTS

irq:    PHA
        LDA $D019
        STA $D019
        LDA $D012
        STA $07
        INC $08
        PLA
        RTI

nmi:    PHA
        LDA $DD0D
        STA $09
        INC $0A
        PLA
        RTI

; ---------------------------------------------------------------- PLA
t_pla:  LDA #$37
        STA $01
        LDA $A000
        STA $05
        EOR #$FF
        STA $06
        STA $A000
        LDA $A000
        CMP $05
        BNE pla1
        LDA #$36
        STA $01
        LDA $A000
        CMP $06
        BNE pla2
        LDA $E000
        STA $05
        EOR #$FF
        STA $06
        STA $E000
        LDA $E000
        CMP $05
        BNE pla3
        LDA #$35
        STA $01
        LDA $E000
        CMP $06
        BNE pla4
        LDA #$03
        STA $D020
        LDA $D020
        CMP #$F3
        BNE pla5
        LDA #$34
        STA $01
        LDA #$5A
        STA $D020
        LDA $D020
        CMP #$5A
        BNE pla6
        LDA #$33
        STA $01
        LDA $D020
        STA $05
        LDA #$A5
        STA $D020
        LDA $D020
        CMP $05
        BNE pla7
        LDA #$34
        STA $01
        LDA $D020
        CMP #$A5
        BNE pla8
        LDA #$35
        STA $01
        LDA #0
        STA $D020
        RTS
pla1:   LDA #1
        BNE plaf
pla2:   LDA #2
        BNE plaf
pla3:   LDA #3
        BNE plaf
pla4:   LDA #4
        BNE plaf
pla5:   LDA #5
        BNE plaf
pla6:   LDA #6
        BNE plaf
pla7:   LDA #7
        BNE plaf
pla8:   LDA #8
plaf:   LDX #$35
        STX $01
        LDX #0
        STX $D020
        RTS

; ---------------------------------------------------------------- keyboard
t_keyboard: LDA #$FF
        STA $DC02
        LDA #0
        STA $DC03
        STA $DC00
        LDA $DC01
        LDX #$FF
        STX $DC00
        CMP #$FF
        BNE kb1
        LDA #0
        RTS
kb1:    LDA #1
        RTS

; ---------------------------------------------------------------- CIA 1 timer A
t_timer: LDA #0
        STA $DC0E
        LDA #$7F
        STA $DC0D
        LDA $DC0D
        LDA #$00
        STA $DC04
        LDA #$02
        STA $DC05
        LDX #0
        LDA #$19
        STA $DC0E
tm_w:   LDA $DC0D
        AND #1
        BNE tm_got
        INX
        BNE tm_w
        LDA #1
        RTS
tm_got: CPX #33
        BCC tm2
        CPX #46
        BCS tm3
        LDA $DC0E
        AND #1
        BNE tm4
        LDA $DC0D
        AND #1
        BNE tm5
        LDA #$11
        STA $DC0E
        NOP
        NOP
        LDA $DC04
        CMP $DC04
        BEQ tm6
        LDA #0
        STA $DC0E
        RTS
tm2:    LDA #2
        RTS
tm3:    LDA #3
        RTS
tm4:    LDA #4
        RTS
tm5:    LDA #5
        RTS
tm6:    LDA #0
        STA $DC0E
        LDA #6
        RTS

; ---------------------------------------------------------------- CIA 1 time of day
t_tod:  LDA #$80
        STA $DC0E
        LDA #0
        STA $DC0F
        LDA #$01
        STA $DC0B
        LDA #0
        STA $DC0A
        STA $DC09
        STA $DC08
        LDX #20
        JSR frames
        LDA $DC0B
        LDA $DC0A
        LDA $DC09
        STA $05
        LDA $DC08
        STA $06
        LDA #0
        STA $DC0E
        LDA $05
        BNE td1
        LDA $06
        CMP #3
        BCC td2
        CMP #5
        BCS td3
        LDA #0
        RTS
td1:    LDA #1
        RTS
td2:    LDA #2
        RTS
td3:    LDA #3
        RTS

; ---------------------------------------------------------------- raster IRQ
t_raster: LDA #0
        STA $08
        STA $07
        LDA #$1B
        STA $D011
        LDA #100
        STA $D012
        LDA #$FF
        STA $D019
        LDA #1
        STA $D01A
        LDX #1
        JSR frames
        LDA #$FF
        STA $D019
        LDA #0
        STA $08
        CLI
        LDX #5
        JSR frames
        SEI
        LDA #0
        STA $D01A
        LDA #$FF
        STA $D019
        LDA $08
        CMP #5
        BNE rs1
        LDA $07
        CMP #100
        BCC rs2
        CMP #102
        BCS rs2
        LDA #0
        RTS
rs1:    LDA #1
        RTS
rs2:    LDA #2
        RTS

; ---------------------------------------------------------------- sprites
; all characters solid except the space (in RAM at $3000, the VIC's $D018 = $1C for the test)
t_sprites: LDX #0
        LDA #$FF
sp_c:   STA $3000,X
        STA $3100,X
        STA $3200,X
        STA $3300,X
        STA $3400,X
        STA $3500,X
        STA $3600,X
        STA $3700,X
        INX
        BNE sp_c
        LDA #0
        LDX #7
sp_s:   STA $3100,X
        DEX
        BPL sp_s
        LDX #62
        LDA #$FF
sp_d:   STA $0340,X
        DEX
        BPL sp_d
        LDA #13
        STA $07F8
        STA $07F9
        STA $07FA
        LDA #0
        STA $D010
        STA $D017
        STA $D01B
        STA $D01C
        STA $D01D
        LDA #150
        STA $D000
        LDA #200
        STA $D001
        LDA #158
        STA $D002
        LDA #205
        STA $D003
        LDA #24
        STA $D004
        LDA #50
        STA $D005
        LDA #7
        STA $D027
        STA $D028
        STA $D029
        LDA #$1C
        STA $D018
        LDA $D01E
        LDA $D01F
        LDA #$07
        STA $D015
        LDX #2
        JSR frames
        LDA $D01E
        STA $05
        LDA $D01F
        STA $06
        LDA #0
        STA $D015
        LDA #$14
        STA $D018
        LDX #1
        JSR frames
        LDA $D01E
        LDA $D01F
        LDA $05
        CMP #$03
        BNE sp1
        LDA $06
        AND #$04
        BEQ sp2
        LDA $06
        AND #$03
        BNE sp3
        LDA #0
        RTS
sp1:    LDA #1
        RTS
sp2:    LDA #2
        RTS
sp3:    LDA #3
        RTS

; ---------------------------------------------------------------- badline
; X = the polling loop's passes while the raster is on line A (11 cycles a pass)
linecount: STA $05
        SEC
        SBC #1
lc1:    CMP $D012
        BNE lc1
        LDA $05
lc2:    CMP $D012
        BNE lc2
        LDX #0
lc3:    INX
        LDA $D012
        CMP $05
        BEQ lc3
        RTS
t_badline: LDA #$1B
        STA $D011
        LDA #91
        JSR linecount
        STX $06
        LDA #93
        JSR linecount
        STX $05
        LDA $06
        CLC
        ADC #2
        CMP $05
        BCS bl1
        LDA #0
        RTS
bl1:    LDA #1
        RTS

; ---------------------------------------------------------------- SID voice 3
t_sid:  LDA #0
        STA $D418
        LDA #$FF
        STA $D40E
        STA $D40F
        LDA #$81
        STA $D412
        LDA $D41B
        STA $05
        LDX #3
        JSR frames
        LDA $D41B
        CMP $05
        BNE sd_n2
        LDX #3
        JSR frames
        LDA $D41B
        CMP $05
        BEQ sd1
sd_n2:  LDA #$00
        STA $D413
        LDA #$F0
        STA $D414
        LDA #$20
        STA $D412
        LDX #2
        JSR frames
        LDA $D41C
        CMP #$10
        BCS sd2
        LDA #$21
        STA $D412
        LDX #1
        JSR frames
        LDA $D41C
        CMP #$F0
        BCC sd3
        LDA #$20
        STA $D412
        LDX #2
        JSR frames
        LDA $D41C
        CMP #$10
        BCS sd4
        LDA #0
        STA $D412
        RTS
sd1:    LDA #1
        RTS
sd2:    LDA #2
        RTS
sd3:    LDA #3
        RTS
sd4:    LDA #4
        RTS

; ---------------------------------------------------------------- CIA 2 NMI
t_nmi:  LDA #0
        STA $0A
        STA $09
        STA $DD0E
        LDA #$7F
        STA $DD0D
        LDA $DD0D
        LDA #$40
        STA $DD04
        LDA #0
        STA $DD05
        LDA #$81
        STA $DD0D
        LDA #$19
        STA $DD0E
        LDX #60
nm_w:   DEX
        BNE nm_w
        LDA #$7F
        STA $DD0D
        LDA $DD0D
        LDA $0A
        CMP #1
        BNE nm1
        LDA $09
        AND #$81
        CMP #$81
        BNE nm2
        LDA #0
        RTS
nm1:    LDA #1
        RTS
nm2:    LDA #2
        RTS

{strings}
"""
    data, labels = md.assemble(src)
    code_len = labels['glyphs'] - md.ORG - 63
    data = data[:code_len]
    assert labels['start'] == 0x080D, hex(labels['start'])
    prg = bytes([md.ORG & 255, md.ORG >> 8]) + bytes(data)
    (ROOT / 'tests' / 'selftest.prg').write_bytes(prg)
    print('selftest:', len(prg), 'bytes, code to', hex(md.ORG + code_len))

main()
