"""Generate the 6510 core twice from one opcode table:

  src/cpu6510.pmi           PureMetal, for the Pico W / Pico 2 W
  desktop/core/cpu6510.pbi  PureBasic (C back end), for the desktop program

Every one of the 256 NMOS opcodes, the undocumented ones included, each with
its own handler reached through a 256-entry computed-goto table.

Memory goes through two page tables, RdMap and WrMap: 256 entries of a BIASED
base address (PeekA(RdMap(a >> 8) + a) is the byte), or 0 for a page the machine
answers itself (I/O, open bus, the CPU port's page 0 for writes). The zero page
and the stack are always RAM (M), except that writes to $00/$01 go to the port.

Timing: CpuRun(n) runs whole instructions until at least n cycles are used and
returns the cycles used. During an instruction, CpuNow() is the machine clock of
the access being made: C64Clock + (Budget - Left) + AccessPhase, where the phase
is the access's cycle within the instruction (the last cycle for ordinary reads
and writes, cycles-3/-2/-1 for a read-modify-write's read, dummy write, write).
"""
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

# ---------------------------------------------------------------- the table
# opcode: (mnemonic, mode, cycles, page-cross penalty)
T = {}
def op(code, mn, mode, cyc, pen=False):
    assert code not in T, hex(code)
    T[code] = (mn, mode, cyc, pen)

ALU = ['ORA', 'AND', 'EOR', 'ADC', 'STA', 'LDA', 'CMP', 'SBC']
for i, mn in enumerate(ALU):
    b = i << 5
    op(b | 0x01, mn, 'izx', 6)
    op(b | 0x11, mn, 'izy', 6 if mn == 'STA' else 5, mn != 'STA')
    op(b | 0x05, mn, 'zp', 3)
    op(b | 0x15, mn, 'zpx', 4)
    op(b | 0x0D, mn, 'abs', 4)
    op(b | 0x1D, mn, 'abx', 5 if mn == 'STA' else 4, mn != 'STA')
    op(b | 0x19, mn, 'aby', 5 if mn == 'STA' else 4, mn != 'STA')
    if mn != 'STA':
        op(b | 0x09, mn, 'imm', 2)
UND = ['SLO', 'RLA', 'SRE', 'RRA', None, None, 'DCP', 'ISC']
for i, mn in enumerate(UND):
    if not mn: continue
    b = i << 5
    op(b | 0x03, mn, 'izx', 8)
    op(b | 0x13, mn, 'izy', 8)
    op(b | 0x07, mn, 'zp', 5)
    op(b | 0x17, mn, 'zpx', 6)
    op(b | 0x0F, mn, 'abs', 6)
    op(b | 0x1F, mn, 'abx', 7)
    op(b | 0x1B, mn, 'aby', 7)
SH = ['ASL', 'ROL', 'LSR', 'ROR']
for i, mn in enumerate(SH):
    b = i << 5
    op(b | 0x0A, mn, 'acc', 2)
    op(b | 0x06, mn, 'zp', 5)
    op(b | 0x16, mn, 'zpx', 6)
    op(b | 0x0E, mn, 'abs', 6)
    op(b | 0x1E, mn, 'abx', 7)
op(0xC6, 'DEC', 'zp', 5); op(0xD6, 'DEC', 'zpx', 6); op(0xCE, 'DEC', 'abs', 6); op(0xDE, 'DEC', 'abx', 7)
op(0xE6, 'INC', 'zp', 5); op(0xF6, 'INC', 'zpx', 6); op(0xEE, 'INC', 'abs', 6); op(0xFE, 'INC', 'abx', 7)
op(0x83, 'SAX', 'izx', 6); op(0x87, 'SAX', 'zp', 3); op(0x97, 'SAX', 'zpy', 4); op(0x8F, 'SAX', 'abs', 4)
op(0xA3, 'LAX', 'izx', 6); op(0xB3, 'LAX', 'izy', 5, True); op(0xA7, 'LAX', 'zp', 3); op(0xB7, 'LAX', 'zpy', 4)
op(0xAF, 'LAX', 'abs', 4); op(0xBF, 'LAX', 'aby', 4, True)
op(0x93, 'SHA', 'izy', 6); op(0x9F, 'SHA', 'aby', 5); op(0x9E, 'SHX', 'aby', 5); op(0x9C, 'SHY', 'abx', 5)
op(0x9B, 'TAS', 'aby', 5); op(0xBB, 'LAS', 'aby', 4, True)
op(0x0B, 'ANC', 'imm', 2); op(0x2B, 'ANC', 'imm', 2); op(0x4B, 'ALR', 'imm', 2); op(0x6B, 'ARR', 'imm', 2)
op(0x8B, 'ANE', 'imm', 2); op(0xAB, 'LXA', 'imm', 2); op(0xCB, 'SBX', 'imm', 2); op(0xEB, 'SBC', 'imm', 2)
op(0xA2, 'LDX', 'imm', 2); op(0xA6, 'LDX', 'zp', 3); op(0xB6, 'LDX', 'zpy', 4); op(0xAE, 'LDX', 'abs', 4); op(0xBE, 'LDX', 'aby', 4, True)
op(0xA0, 'LDY', 'imm', 2); op(0xA4, 'LDY', 'zp', 3); op(0xB4, 'LDY', 'zpx', 4); op(0xAC, 'LDY', 'abs', 4); op(0xBC, 'LDY', 'abx', 4, True)
op(0x86, 'STX', 'zp', 3); op(0x96, 'STX', 'zpy', 4); op(0x8E, 'STX', 'abs', 4)
op(0x84, 'STY', 'zp', 3); op(0x94, 'STY', 'zpx', 4); op(0x8C, 'STY', 'abs', 4)
op(0xE0, 'CPX', 'imm', 2); op(0xE4, 'CPX', 'zp', 3); op(0xEC, 'CPX', 'abs', 4)
op(0xC0, 'CPY', 'imm', 2); op(0xC4, 'CPY', 'zp', 3); op(0xCC, 'CPY', 'abs', 4)
op(0x24, 'BIT', 'zp', 3); op(0x2C, 'BIT', 'abs', 4)
for code, mn in [(0x10, 'BPL'), (0x30, 'BMI'), (0x50, 'BVC'), (0x70, 'BVS'), (0x90, 'BCC'), (0xB0, 'BCS'), (0xD0, 'BNE'), (0xF0, 'BEQ')]:
    op(code, mn, 'rel', 2)
op(0x00, 'BRK', 'imp', 7); op(0x20, 'JSR', 'abs', 6); op(0x40, 'RTI', 'imp', 6); op(0x60, 'RTS', 'imp', 6)
op(0x4C, 'JMP', 'abs', 3); op(0x6C, 'JMP', 'ind', 5)
for code, mn, cyc in [(0x08, 'PHP', 3), (0x28, 'PLP', 4), (0x48, 'PHA', 3), (0x68, 'PLA', 4),
                      (0x18, 'CLC', 2), (0x38, 'SEC', 2), (0x58, 'CLI', 2), (0x78, 'SEI', 2),
                      (0xB8, 'CLV', 2), (0xD8, 'CLD', 2), (0xF8, 'SED', 2),
                      (0x88, 'DEY', 2), (0xC8, 'INY', 2), (0xCA, 'DEX', 2), (0xE8, 'INX', 2),
                      (0x8A, 'TXA', 2), (0x98, 'TYA', 2), (0xA8, 'TAY', 2), (0xAA, 'TAX', 2),
                      (0x9A, 'TXS', 2), (0xBA, 'TSX', 2), (0xEA, 'NOP', 2)]:
    op(code, mn, 'imp', cyc)
for code in (0x1A, 0x3A, 0x5A, 0x7A, 0xDA, 0xFA): op(code, 'NOP', 'imp', 2)
for code in (0x80, 0x82, 0x89, 0xC2, 0xE2): op(code, 'NOP', 'imm', 2)
for code in (0x04, 0x44, 0x64): op(code, 'NOP', 'zp', 3)
for code in (0x14, 0x34, 0x54, 0x74, 0xD4, 0xF4): op(code, 'NOP', 'zpx', 4)
op(0x0C, 'NOP', 'abs', 4)
for code in (0x1C, 0x3C, 0x5C, 0x7C, 0xDC, 0xFC): op(code, 'NOP', 'abx', 4, True)
for code in (0x02, 0x12, 0x22, 0x32, 0x42, 0x52, 0x62, 0x72, 0x92, 0xB2, 0xD2, 0xF2): op(code, 'JAM', 'imp', 2)
assert len(T) == 256, len(T)

# ---------------------------------------------------------------- emitters
def rd(dst, addr, phase):
    """Read through the page table into dst."""
    return [f'  Pg = RdMap({addr} >> 8)',
            f'  If Pg : {dst} = PeekA(Pg + {addr}) : Else : AccessPhase = {phase} : {dst} = C64IoRead({addr}) : EndIf']

def wr(addr, val, phase):
    return [f'  Pg = WrMap({addr} >> 8)',
            f'  If Pg : PokeA(Pg + {addr}, {val}) : Else : AccessPhase = {phase} : C64IoWrite({addr}, {val}) : EndIf']

def fetch(dst):
    return rd(dst, 'PC', 0) + ['  PC = (PC + 1) & $FFFF']

def zpwr(addr, val):
    return [f'  If {addr} < 2 : C64PortWrite({addr}, {val}) : Else : M({addr}) = {val} : EndIf']

def address(mode, pen, kind):
    """Lines that leave the effective address in Ea. kind: 'r', 'w' or 'm' (read-modify-write)."""
    L = []
    if mode == 'zp':
        L += fetch('Ea')
    elif mode in ('zpx', 'zpy'):
        r = 'X' if mode == 'zpx' else 'Y'
        L += fetch('Ea') + [f'  Ea = (Ea + {r}) & 255']
    elif mode in ('abs', 'abx', 'aby'):
        L += fetch('Lo') + fetch('Hi') + ['  Ea = Lo | (Hi << 8)']
        if mode != 'abs':
            r = 'X' if mode == 'abx' else 'Y'
            L += ['  Base = Ea', f'  Ea = (Ea + {r}) & $FFFF']
            if pen:
                L += ['  If (Base & $FF00) <> (Ea & $FF00) : Left = Left - 1 : EndIf']
    elif mode == 'izx':
        L += fetch('Tmp') + ['  Tmp = (Tmp + X) & 255', '  Ea = M(Tmp) | (M((Tmp + 1) & 255) << 8)']
    elif mode == 'izy':
        L += fetch('Tmp') + ['  Ea = M(Tmp) | (M((Tmp + 1) & 255) << 8)', '  Base = Ea', '  Ea = (Ea + Y) & $FFFF']
        if pen:
            L += ['  If (Base & $FF00) <> (Ea & $FF00) : Left = Left - 1 : EndIf']
    else:
        raise ValueError(mode)
    return L

ZPMODES = ('zp', 'zpx', 'zpy')

def operand(mode, pen, cyc):
    """Value <- the operand of a read instruction."""
    if mode == 'imm':
        return fetch('Value')
    L = address(mode, pen, 'r')
    if mode in ZPMODES:
        L += ['  Value = M(Ea)']
    else:
        L += rd('Value', 'Ea', cyc - 1)
    return L

def store(mode, cyc, val):
    L = address(mode, False, 'w')
    if mode in ZPMODES:
        L += zpwr('Ea', val)
    else:
        L += wr('Ea', val, cyc - 1)
    return L

def rmw(mode, cyc, body):
    """Read Value, run body (leaves Res), write old then new (the NMOS double write)."""
    L = address(mode, False, 'm')
    if mode in ZPMODES:
        L += ['  Value = M(Ea)'] + body + zpwr('Ea', 'Res')
    else:
        L += ['  Pg = RdMap(Ea >> 8)',
              f'  If Pg : Value = PeekA(Pg + Ea) : Else : AccessPhase = {cyc - 3} : Value = C64IoRead(Ea) : EndIf']
        L += body
        L += ['  Pg = WrMap(Ea >> 8)',
              '  If Pg',
              '    PokeA(Pg + Ea, Res)',
              '  Else',
              f'    AccessPhase = {cyc - 2} : C64IoWrite(Ea, Value)',
              f'    AccessPhase = {cyc - 1} : C64IoWrite(Ea, Res)',
              '  EndIf']
    return L

NZ = lambda v: [f'  FN = {v}', f'  FZ = {v}']

ADC = ['  Res = A + Value + ((FC >> 8) & 1)',
       '  If FD',
       '    FZ = Res',
       '    Lo = (A & 15) + (Value & 15) + ((FC >> 8) & 1)',
       '    If Lo > 9 : Lo = ((Lo + 6) & 15) + 16 : EndIf',
       '    Hi = (A & $F0) + (Value & $F0) + Lo',
       '    FN = Hi',
       '    FV = (~(A ! Value)) & (A ! Hi)',
       '    If Hi > $9F : Hi = Hi + $60 : EndIf',
       '    FC = 0',
       '    If Hi > 255 : FC = $100 : EndIf',
       '    A = Hi & 255',
       '  Else',
       '    FV = (~(A ! Value)) & (A ! Res)',
       '    FC = Res',
       '    A = Res & 255',
       '    FN = A',
       '    FZ = A',
       '  EndIf']
SBC = ['  Tmp = ((FC >> 8) & 1) ! 1',
       '  Res = A - Value - Tmp',
       '  FV = (A ! Value) & (A ! Res)',
       '  FC = ~Res',
       '  FN = Res',
       '  FZ = Res & 255',
       '  If FD',
       '    Lo = (A & 15) - (Value & 15) - Tmp',
       '    Hi = (A & $F0) - (Value & $F0)',
       '    If Lo < 0 : Lo = ((Lo - 6) & 15) - 16 : EndIf',
       '    Hi = Hi + Lo',
       '    If Hi < 0 : Hi = Hi - $60 : EndIf',
       '    A = Hi & 255',
       '  Else',
       '    A = Res & 255',
       '  EndIf']
def CMP(r):
    return [f'  Res = {r} - Value', '  FC = ~Res', '  FN = Res', '  FZ = Res & 255']

SHIFT = {
    'ASL': ['  Res = Value << 1', '  FC = Res', '  Res = Res & 255'] + NZ('Res'),
    'ROL': ['  Res = (Value << 1) | ((FC >> 8) & 1)', '  FC = Res', '  Res = Res & 255'] + NZ('Res'),
    'LSR': ['  FC = (Value & 1) << 8', '  Res = Value >> 1'] + NZ('Res'),
    'ROR': ['  Res = (Value >> 1) | ((FC >> 1) & $80)', '  FC = (Value & 1) << 8'] + NZ('Res'),
    'INC': ['  Res = (Value + 1) & 255'] + NZ('Res'),
    'DEC': ['  Res = (Value - 1) & 255'] + NZ('Res'),
}

def tail(c, extra=None):
    return (extra or []) + [f'  CpuNextOp({c})']

def stop_if_irq():
    # I just cleared with an IRQ pending: end the window so the machine takes it.
    return ['  If FI = 0 And C64IrqLine <> 0 : Budget = Budget - Left : Left = 0 : EndIf']

def body(code):
    mn, mode, cyc, pen = T[code]
    L = []
    if mn in ('ORA', 'AND', 'EOR'):
        o = {'ORA': '|', 'AND': '&', 'EOR': '!'}[mn]
        L += operand(mode, pen, cyc) + [f'  A = A {o} Value'] + NZ('A')
    elif mn == 'ADC':
        L += operand(mode, pen, cyc) + ADC
    elif mn == 'SBC':
        L += operand(mode, pen, cyc) + SBC
    elif mn == 'CMP':
        L += operand(mode, pen, cyc) + CMP('A')
    elif mn == 'CPX':
        L += operand(mode, pen, cyc) + CMP('X')
    elif mn == 'CPY':
        L += operand(mode, pen, cyc) + CMP('Y')
    elif mn in ('LDA', 'LDX', 'LDY'):
        r = mn[2]
        L += operand(mode, pen, cyc) + [f'  {r} = Value'] + NZ(r)
    elif mn == 'LAX':
        L += operand(mode, pen, cyc) + ['  A = Value', '  X = Value'] + NZ('A')
    elif mn == 'NOP':
        if mode == 'imp':
            pass
        elif mode == 'imm':
            L += ['  PC = (PC + 1) & $FFFF']
        else:
            L += operand(mode, pen, cyc)
    elif mn in ('STA', 'STX', 'STY'):
        L += store(mode, cyc, mn[2])
    elif mn == 'SAX':
        L += ['  Res = A & X'] + store(mode, cyc, 'Res')
    elif mn == 'BIT':
        L += operand(mode, pen, cyc) + ['  FN = Value', '  FV = Value << 1', '  FZ = A & Value']
    elif mn in SHIFT and mode == 'acc':
        L += ['  Value = A'] + SHIFT[mn] + ['  A = Res']
    elif mn in SHIFT:
        L += rmw(mode, cyc, SHIFT[mn])
    elif mn == 'SLO':
        L += rmw(mode, cyc, SHIFT['ASL']) + ['  A = A | Res'] + NZ('A')
    elif mn == 'RLA':
        L += rmw(mode, cyc, SHIFT['ROL']) + ['  A = A & Res'] + NZ('A')
    elif mn == 'SRE':
        L += rmw(mode, cyc, SHIFT['LSR']) + ['  A = A ! Res'] + NZ('A')
    elif mn == 'RRA':
        L += rmw(mode, cyc, SHIFT['ROR']) + ['  Value = Res'] + ADC
    elif mn == 'DCP':
        L += rmw(mode, cyc, ['  Res = (Value - 1) & 255']) + ['  Value = Res'] + CMP('A')
    elif mn == 'ISC':
        L += rmw(mode, cyc, ['  Res = (Value + 1) & 255']) + ['  Value = Res'] + SBC
    elif mn in ('SHA', 'SHX', 'SHY', 'TAS'):
        # value & (high byte of the base address + 1); on a page cross the
        # high byte of the address becomes that value (the unstable NMOS store).
        src = {'SHA': 'A & X', 'SHX': 'X', 'SHY': 'Y', 'TAS': 'A & X'}[mn]
        L += address(mode, False, 'w')
        if mn == 'TAS':
            L += ['  S = A & X']
            src = 'S'
        L += [f'  Res = ({src}) & (((Base >> 8) + 1) & 255)',
              '  If (Base & $FF00) <> (Ea & $FF00) : Ea = (Ea & 255) | (Res << 8) : EndIf']
        L += wr('Ea', 'Res', cyc - 1)
    elif mn == 'LAS':
        L += operand(mode, pen, cyc) + ['  A = Value & S', '  X = A', '  S = A'] + NZ('A')
    elif mn == 'ANC':
        L += fetch('Value') + ['  A = A & Value'] + NZ('A') + ['  FC = A << 1']
    elif mn == 'ALR':
        L += fetch('Value') + ['  A = A & Value', '  FC = (A & 1) << 8', '  A = A >> 1'] + NZ('A')
    elif mn == 'ARR':
        L += fetch('Value') + [
            '  Tmp = A & Value',
            '  Res = (Tmp >> 1) | ((FC >> 1) & $80)',
            '  If FD',
            '    FN = (FC >> 1) & $80',
            '    FZ = Res',
            '    FV = (Res ! Tmp) << 1',
            '    If (Tmp & 15) + (Tmp & 1) > 5 : Res = (Res & $F0) | ((Res + 6) & 15) : EndIf',
            '    If (Tmp & $F0) + (Tmp & $10) > $50',
            '      Res = (Res & 15) | ((Res + $60) & $F0)',
            '      FC = $100',
            '    Else',
            '      FC = 0',
            '    EndIf',
            '    A = Res',
            '  Else',
            '    A = Res',
            '    FN = A',
            '    FZ = A',
            '    FC = (A & $40) << 2',
            '    FV = ((A & $40) ! ((A & $20) << 1)) << 1',
            '  EndIf']
    elif mn == 'ANE':
        L += fetch('Value') + ['  A = (A | $EE) & X & Value'] + NZ('A')
    elif mn == 'LXA':
        L += fetch('Value') + ['  A = (A | $EE) & Value', '  X = A'] + NZ('A')
    elif mn == 'SBX':
        L += fetch('Value') + ['  Res = (A & X) - Value', '  FC = ~Res', '  X = Res & 255'] + NZ('X')
    elif mn in ('BPL', 'BMI', 'BVC', 'BVS', 'BCC', 'BCS', 'BNE', 'BEQ'):
        cond = {'BPL': '(FN & $80) = 0', 'BMI': '(FN & $80) <> 0', 'BVC': '(FV & $80) = 0',
                'BVS': '(FV & $80) <> 0', 'BCC': '(FC & $100) = 0', 'BCS': '(FC & $100) <> 0',
                'BNE': '(FZ & 255) <> 0', 'BEQ': '(FZ & 255) = 0'}[mn]
        L += fetch('Value')
        L += [f'  If {cond}',
              '    Base = PC',
              '    PC = (PC + ((Value ! 128) - 128)) & $FFFF',
              '    Left = Left - 1',
              '    If (Base & $FF00) <> (PC & $FF00) : Left = Left - 1 : EndIf',
              '  EndIf']
    elif mn == 'BRK':
        L += ['  PC = (PC + 1) & $FFFF', '  CpuPush(PC >> 8)', '  CpuPush(PC & 255)',
              '  Tmp = CpuStatus() | $10', '  CpuPush(Tmp)', '  FI = 1']
        L += rd('Lo', '$FFFE', 5) + rd('Hi', '$FFFF', 6) + ['  PC = Lo | (Hi << 8)']
    elif mn == 'JSR':
        # The high operand byte is fetched after the stack writes.
        L += fetch('Lo') + ['  CpuPush(PC >> 8)', '  CpuPush(PC & 255)'] + rd('Hi', 'PC', 5) + ['  PC = Lo | (Hi << 8)']
    elif mn == 'RTS':
        L += ['  CpuPop(Lo)', '  CpuPop(Hi)', '  PC = ((Lo | (Hi << 8)) + 1) & $FFFF']
    elif mn == 'RTI':
        L += ['  CpuPop(Tmp)', '  CpuSetStatus(Tmp)', '  CpuPop(Lo)', '  CpuPop(Hi)', '  PC = Lo | (Hi << 8)'] + stop_if_irq()
    elif mn == 'JMP' and mode == 'abs':
        L += fetch('Lo') + fetch('Hi') + ['  PC = Lo | (Hi << 8)']
    elif mn == 'JMP':
        L += fetch('Lo') + fetch('Hi') + ['  Ea = Lo | (Hi << 8)'] + rd('Lo', 'Ea', 3)
        L += ['  Ea = (Ea & $FF00) | ((Ea + 1) & 255)'] + rd('Hi', 'Ea', 4) + ['  PC = Lo | (Hi << 8)']
    elif mn == 'PHP':
        L += ['  Tmp = CpuStatus() | $10', '  CpuPush(Tmp)']
    elif mn == 'PLP':
        L += ['  CpuPop(Tmp)', '  CpuSetStatus(Tmp)'] + stop_if_irq()
    elif mn == 'PHA':
        L += ['  CpuPush(A)']
    elif mn == 'PLA':
        L += ['  CpuPop(A)'] + NZ('A')
    elif mn == 'CLC': L += ['  FC = 0']
    elif mn == 'SEC': L += ['  FC = $100']
    elif mn == 'CLI': L += ['  FI = 0'] + stop_if_irq()
    elif mn == 'SEI': L += ['  FI = 1']
    elif mn == 'CLV': L += ['  FV = 0']
    elif mn == 'CLD': L += ['  FD = 0']
    elif mn == 'SED': L += ['  FD = 1']
    elif mn in ('INX', 'INY', 'DEX', 'DEY'):
        r = mn[2]; d = '+' if mn[0] == 'I' else '-'
        L += [f'  {r} = ({r} {d} 1) & 255'] + NZ(r)
    elif mn in ('TAX', 'TAY', 'TXA', 'TYA', 'TSX'):
        src = {'TAX': 'A', 'TAY': 'A', 'TXA': 'X', 'TYA': 'Y', 'TSX': 'S'}[mn]
        dst = {'TAX': 'X', 'TAY': 'Y', 'TXA': 'A', 'TYA': 'A', 'TSX': 'X'}[mn]
        L += [f'  {dst} = {src}'] + NZ(dst)
    elif mn == 'TXS':
        L += ['  S = X']
    elif mn == 'JAM':
        # $02 doubles as the machine's trap: C64Trap answers 1 when it handled
        # the address (a patched ROM entry point), else the CPU jams.
        L += ['  If C64Trap((PC - 1) & $FFFF)',
              '    If Stopped : Left = Left - 2 : Goto Done : EndIf',
              '  Else',
              '    PC = (PC - 1) & $FFFF',
              f'    BadOpcode = ${code:02X}',
              '    Stopped = 1',
              '    Left = Left - 2',
              '    Goto Done',
              '  EndIf']
    else:
        raise ValueError(mn)
    return L + tail(cyc)

# ---------------------------------------------------------------- the file
HEAD = '''; GENERATED by tools/gen_cpu.py - do not edit; regenerate.
; MOS 6510: every NMOS 6502 opcode, the undocumented ones included, through a
; 256-entry computed-goto table. Memory through RdMap/WrMap (biased page bases,
; 0 = the machine answers: C64IoRead / C64IoWrite); zero page and stack are RAM
; (M), writes to $00/$01 go to C64PortWrite. CpuRun(n) runs whole instructions
; until n cycles are used and returns the cycles used.
Global Dim M.a(65536)
Global Dim RdMap.i(256)
Global Dim WrMap.i(256)
Global Dim Dispatch.{LABEL}(256)
Global PC.i, A.i, X.i, Y.i, S.i
Global FN.i, FZ.i, FC.i, FV.i, FD.i, FI.i
Global Res.i, Left.i, Budget.i, Ready.i, Stopped.i, BadOpcode.i
Global Ea.i, Value.i, Lo.i, Hi.i, Tmp.i, Base.i, Pg.i
Global AccessPhase.i, CpuInstructions.i, InitIndex.i
Global C64Clock.i, C64IrqLine.i
{RESERVE}
Declare.i C64IoRead(addr.i)
Declare C64IoWrite(addr.i, v.i)
Declare C64PortWrite(addr.i, v.i)
Declare.i C64Trap(addr.i)

; N is bit 7 of FN; Z means the low byte of FZ is zero; C is bit 8 of FC;
; V is bit 7 of FV; D and I are 0 or 1.
Macro CpuPush(v)
  M($100 + S) = v
  S = (S - 1) & 255
EndMacro
Macro CpuPop(v)
  S = (S + 1) & 255
  v = M($100 + S)
EndMacro
; The machine clock of the access being made now (valid inside CpuRun).
Macro CpuNow()
  (C64Clock + Budget - Left + AccessPhase)
EndMacro
Procedure.i CpuStatus()
  Protected p.i
  p = $20 | (FN & $80) | ((FV & $80) >> 1) | (FD << 3) | (FI << 2) | ((FC >> 8) & 1)
  If (FZ & 255) = 0
    p = p | 2
  EndIf
  ProcedureReturn p
EndProcedure
Procedure CpuSetStatus(p.i)
  FN = p
  FV = p << 1
  FC = (p & 1) << 8
  FZ = (p & 2) ! 2
  FD = (p >> 3) & 1
  FI = (p >> 2) & 1
EndProcedure
Procedure.i CpuReadVector(addr.i)
  Protected lo.i, hi.i
  Pg = RdMap(addr >> 8)
  If Pg : lo = PeekA(Pg + addr) : hi = PeekA(Pg + addr + 1) : Else : lo = C64IoRead(addr) : hi = C64IoRead(addr + 1) : EndIf
  ProcedureReturn lo | (hi << 8)
EndProcedure
Procedure CpuReset()
  PC = CpuReadVector($FFFC)
  A = 0 : X = 0 : Y = 0 : S = $FD
  CpuSetStatus($24)
  Stopped = 0 : BadOpcode = 0
EndProcedure
; The machine calls this BETWEEN run windows: NMI ($FFFA), or IRQ ($FFFE) when
; I is clear. Returns the cycles it took (7), or 0 when not taken.
Procedure.i CpuInterrupt(vector.i)
  If Stopped
    ProcedureReturn 0
  EndIf
  If vector = $FFFE And FI
    ProcedureReturn 0
  EndIf
  CpuPush(PC >> 8)
  CpuPush(PC & 255)
  Tmp = CpuStatus()
  CpuPush(Tmp)
  FI = 1
  PC = CpuReadVector(vector)
  ProcedureReturn 7
EndProcedure

{PROC}.i CpuRun(n.i)
Macro CpuDispatchNext()
  Pg = RdMap(PC >> 8)
  If Pg : Tmp = PeekA(Pg + PC) : Else : AccessPhase = 0 : Tmp = C64IoRead(PC) : EndIf
  PC = (PC + 1) & $FFFF
  {GOTO}
EndMacro
Macro CpuNextOp(c)
  Left = Left - c
  CpuInstructions = CpuInstructions + 1
  If Left <= 0
    Goto Done
  EndIf
  CpuDispatchNext()
EndMacro
  If Ready = 0
    For InitIndex = 0 To 255
      Dispatch(InitIndex) = ?Op00
    Next
{TABLE}
    Ready = 1
  EndIf
  Budget = n
  Left = n
  If Stopped Or n <= 0
    ProcedureReturn n
  EndIf
  CpuDispatchNext()
'''

FOOT = '''Done:
  ProcedureReturn Budget - Left
EndProcedure
'''

def generate(lang):
    out = []
    for code in range(256):
        mn, mode, cyc, pen = T[code]
        out.append(f'Op{code:02X}: ; ${code:02X} {mn} {mode}')
        b = body(code)
        out += b
    table = '\n'.join(f'    Dispatch(${c:02X}) = ?Op{c:02X}' for c in range(256))
    if lang == 'pm':
        # The hot CPU variables live in registers (the 6502 core's precedent): 10 KB less code, faster.
        # Application-wide: no other code gets r4, r5, r8-r11.
        head = HEAD.replace('{LABEL}', 'Label').replace('{PROC}', 'ProcedureRAM').replace('{GOTO}', 'Goto Dispatch(Tmp)').replace(
            '{RESERVE}', 'ReserveRegister PC = r8, A = r9, Res = r10, Left = r11, X = r4, Pg = r5\n')
    else:
        head = HEAD.replace('{RESERVE}', '').replace('{LABEL}', 'i').replace('{PROC}', 'Procedure').replace(
            '{GOTO}', '!goto *(void*)((integer*)a_dispatch.a)[g_tmp];')
    s = head.replace('{TABLE}', table) + '\n'.join(out) + '\n' + FOOT
    if lang == 'pm':
        # CpuNextOp counts instructions only on the window's last one above;
        # keep a running count for the speed report as well.
        pass
    return s

def main():
    (ROOT / 'src').mkdir(exist_ok=True)
    (ROOT / 'desktop' / 'core').mkdir(parents=True, exist_ok=True)
    (ROOT / 'src' / 'cpu6510.pmi').write_text(generate('pm'), newline='\n')
    (ROOT / 'desktop' / 'core' / 'cpu6510.pbi').write_text(generate('pb'), newline='\n')
    # a mnemonic / mode / cycles table for the disassemblers and the tests
    rows = []
    for c in range(256):
        mn, mode, cyc, pen = T[c]
        rows.append(f'{c:02X} {mn} {mode} {cyc} {int(pen)}')
    (ROOT / 'tools' / 'opcodes.txt').write_text('\n'.join(rows) + '\n', newline='\n')
    # the desktop disassembler's table: mnemonic and addressing mode per opcode
    modes = ['imp', 'acc', 'imm', 'zp', 'zpx', 'zpy', 'abs', 'abx', 'aby', 'ind', 'izx', 'izy', 'rel']
    lines = ['; GENERATED by tools/gen_cpu.py - the disassembler table (mnemonic, mode, cycles).',
             '; modes: ' + ' '.join(f'{i}={m}' for i, m in enumerate(modes)), 'DataSection', 'DisTable:']
    for c in range(256):
        mn, mode, cyc, pen = T[c]
        lines.append(f'  Data.s "{mn}" : Data.i {modes.index(mode)}, {cyc}')
    lines.append('EndDataSection')
    (ROOT / 'desktop' / 'core' / 'opcodes.pbi').write_text('\n'.join(lines) + '\n', newline='\n')
    print('generated: 256 opcodes')

if __name__ == '__main__':
    main()
