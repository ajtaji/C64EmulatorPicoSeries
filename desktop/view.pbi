; What the window shows: the C64's screen and the debug panes (CPU, VIC-II, SID, CIAs, Tests, Programs).
; Every read here is side-effect free: memory through the CPU's page tables without touching I/O.
EnableExplicit
XIncludeFile "core/opcodes.pbi"

Structure ViewTexture
  sprite.GLSprite
  *pixels
EndStructure

Global ViewScreen.ViewTexture
Global Dim ViewPal.l(32)
Global Dim DisName.s(256)
Global Dim DisMode.i(256)
Global Dim DisCycles.i(256)
Global ViewMemPage.i = 8, ViewTestResult$, ViewTestFailed.i, ViewTestLog$
Global ViewFilesTop.i, ViewFolder$, ViewCurrent$
Global NewList ViewFiles.s()
Global Dim ScreenFrame.a(384 * 272)

; --pointer-test (c64_desktop.pb): where each control was last drawn, in canvas units (physical pixels),
; and the control a synthetic press landed on - under the test a press is recorded, never acted on.
Global PtOn.i, PtClicked$
Structure CtlRect : x.f : y.f : w.f : h.f : EndStructure
Global NewMap Ctl.CtlRect()
Procedure CtlSet(name$, x.f, y.f, w.f, h.f)
  Ctl(name$)\x = x : Ctl()\y = y : Ctl()\w = w : Ctl()\h = h
EndProcedure
Procedure.b Btn(name$, x.f, y.f, w.f, h.f, label.s, lit.b = #False)
  CtlSet(name$, x, y, w, h)
  If Neon_Button(x, y, w, h, label, lit)
    If PtOn : PtClicked$ = name$ : ProcedureReturn #False : EndIf
    ProcedureReturn #True
  EndIf
  ProcedureReturn #False
EndProcedure

Procedure ViewTextureMake(*t.ViewTexture, w.i, h.i)
  *t\sprite\Width = w : *t\sprite\Height = h
  *t\pixels = AllocateMemory(w * h * 4)
  glGenTextures_(1, @*t\sprite\TextureID) : glBindTexture_(#GL_TEXTURE_2D, *t\sprite\TextureID)
  glTexParameteri_(#GL_TEXTURE_2D, #GL_TEXTURE_MIN_FILTER, #GL_NEAREST)
  glTexParameteri_(#GL_TEXTURE_2D, #GL_TEXTURE_MAG_FILTER, #GL_NEAREST)
  glTexParameteri_(#GL_TEXTURE_2D, #GL_TEXTURE_WRAP_S, #GL_CLAMP_TO_EDGE)
  glTexParameteri_(#GL_TEXTURE_2D, #GL_TEXTURE_WRAP_T, #GL_CLAMP_TO_EDGE)
  glTexImage2D_(#GL_TEXTURE_2D, 0, #GL_RGBA, w, h, 0, #GL_RGBA, #GL_UNSIGNED_BYTE, *t\pixels)
EndProcedure
; The engine's sprite draw samples a Windows texture bottom-up (its images come from DIBs).
Procedure.i ViewRow(*t.ViewTexture, y.i)
  CompilerIf #PB_Compiler_OS = #PB_OS_Windows
    ProcedureReturn *t\pixels + (*t\sprite\Height - 1 - y) * *t\sprite\Width * 4
  CompilerElse
    ProcedureReturn *t\pixels + y * *t\sprite\Width * 4
  CompilerEndIf
EndProcedure
Procedure ViewTextureUpload(*t.ViewTexture)
  glBindTexture_(#GL_TEXTURE_2D, *t\sprite\TextureID)
  glTexSubImage2D_(#GL_TEXTURE_2D, 0, 0, 0, *t\sprite\Width, *t\sprite\Height, #GL_RGBA, #GL_UNSIGNED_BYTE, *t\pixels)
EndProcedure
Procedure ViewTextureDraw(*t.ViewTexture, x.f, y.f, scale.f)
  DrawGLSprite(@*t\sprite, x, y, 0.0, scale, 1.0, 1.0, 1.0, 1.0, #True, -1, -1, -1, -1, #True)
EndProcedure

Procedure ViewInit()
  Protected i.i, r.i, g.i, b.i
  For i = 0 To 15
    r = PeekA(?ViewPalette + i * 3) : g = PeekA(?ViewPalette + i * 3 + 1) : b = PeekA(?ViewPalette + i * 3 + 2)
    ViewPal(i) = r | (g << 8) | (b << 16) | $FF000000
    ViewPal(i + 16) = ViewPal(i)
  Next
  Restore DisTable
  For i = 0 To 255
    Read.s DisName(i) : Read.i DisMode(i) : Read.i DisCycles(i)
  Next
  ViewTextureMake(@ViewScreen, 384, 272)
EndProcedure

; ---------------------------------------------------------------- side-effect-free reads
Procedure.i ViewPeek(addr.i)
  Protected pg.i
  addr & $FFFF
  pg = RdMap(addr >> 8)
  If pg : ProcedureReturn PeekA(pg + addr) : EndIf
  If addr >= $D800 And addr <= $DBFF And C64IoVisible : ProcedureReturn ColorRam(addr & $3FF) | $F0 : EndIf
  ProcedureReturn -1
EndProcedure
Procedure.i ViewPeekByte(addr.i)
  Protected v.i = ViewPeek(addr)
  If v < 0 : v = 0 : EndIf
  ProcedureReturn v
EndProcedure

Procedure.s Hex2(v.i)
  ProcedureReturn RSet(Hex(v & 255), 2, "0")
EndProcedure
Procedure.s Hex4(v.i)
  ProcedureReturn RSet(Hex(v & $FFFF), 4, "0")
EndProcedure

Procedure.i DisLength(op.i)
  Select DisMode(op & 255)
    Case 0, 1 : ProcedureReturn 1
    Case 6, 7, 8, 9 : ProcedureReturn 3
  EndSelect
  ProcedureReturn 2
EndProcedure
Procedure.s DisLine(addr.i)
  Protected op.i, lo.i, hi.i, t$, w.i
  op = ViewPeekByte(addr) : lo = ViewPeekByte(addr + 1) : hi = ViewPeekByte(addr + 2) : w = lo | (hi << 8)
  t$ = Hex4(addr) + "  " + Hex2(op)
  Select DisLength(op)
    Case 1 : t$ + "       "
    Case 2 : t$ + " " + Hex2(lo) + "    "
    Default : t$ + " " + Hex2(lo) + " " + Hex2(hi) + " "
  EndSelect
  t$ + DisName(op) + " "
  Select DisMode(op)
    Case 1 : t$ + "A"
    Case 2 : t$ + "#$" + Hex2(lo)
    Case 3 : t$ + "$" + Hex2(lo)
    Case 4 : t$ + "$" + Hex2(lo) + ",X"
    Case 5 : t$ + "$" + Hex2(lo) + ",Y"
    Case 6 : t$ + "$" + Hex4(w)
    Case 7 : t$ + "$" + Hex4(w) + ",X"
    Case 8 : t$ + "$" + Hex4(w) + ",Y"
    Case 9 : t$ + "($" + Hex4(w) + ")"
    Case 10 : t$ + "($" + Hex2(lo) + ",X)"
    Case 11 : t$ + "($" + Hex2(lo) + "),Y"
    Case 12 : t$ + "$" + Hex4(addr + 2 + ((lo ! 128) - 128))
  EndSelect
  ProcedureReturn t$
EndProcedure

; ---------------------------------------------------------------- the screen
Procedure ViewDrawScreen(x.f, y.f, scale.f)
  Protected *dst.Long, yy.i, xx.i, *src
  For yy = 0 To 271
    *dst = ViewRow(@ViewScreen, yy)
    *src = @ScreenFrame(yy * 384)
    For xx = 0 To 383
      *dst\l = ViewPal(PeekA(*src + xx) & 31) : *dst + 4
    Next
  Next
  ViewTextureUpload(@ViewScreen)
  Neon_Box(x - 2, y - 2, 384 * scale + 4, 272 * scale + 4, 0, 0, 0)
  ViewTextureDraw(@ViewScreen, x, y, scale)
EndProcedure

Procedure.f ViewLine(x.f, y.f, t$, r.f = -1, g.f = 0, b.f = 0)
  If r < 0 : r = Neon_C_TextR : g = Neon_C_TextG : b = Neon_C_TextB : EndIf
  Neon_Text(*Neon_FontMono, x, y, t$, r, g, b)
  ProcedureReturn y + GLFontLineHeight(*Neon_FontMono)
EndProcedure
Procedure.f ViewHead(x.f, y.f, t$)
  Neon_Text(*Neon_FontSmall, x, y, t$, Neon_C_AmbR, Neon_C_AmbG, Neon_C_AmbB)
  ProcedureReturn y + GLFontLineHeight(*Neon_FontMono) + Neon_S(2)
EndProcedure

; ---------------------------------------------------------------- panes
Procedure ViewCpu(x.f, y.f, w.f, h.f)
  Protected p.i, i.i, a.i, row$, v.i
  p = CpuStatus()
  For i = 0 To 7
    If p & (128 >> i) : row$ + Mid("NV-BDIZC", i + 1, 1) : Else : row$ + "." : EndIf
  Next
  Neon_Panel(x, y, w, h, "6510 CPU", Neon_C_AccR, Neon_C_AccG, Neon_C_AccB)
  y + Neon_S(34) : x + Neon_S(12)
  y = ViewLine(x, y, "PC $" + Hex4(PC) + "   A $" + Hex2(A) + "   X $" + Hex2(X) + "   Y $" + Hex2(Y) + "   S $" + Hex2(S) + "   P " + row$)
  y = ViewLine(x, y, "port DDR $" + Hex2(PortDdr) + "  data $" + Hex2(PortData) + "  mode " + Str(C64Mode) + "  EXROM " + Str(CartExrom) + " GAME " + Str(CartGame) + "   IRQ " + Str(C64IrqLine) + "  NMI " + Str(C64NmiLevel))
  y = ViewLine(x, y, "clock " + Str(C64Clock) + "   instructions " + Str(CpuInstructions) + "   frame " + Str(C64Frame), Neon_C_DimR, Neon_C_DimG, Neon_C_DimB)
  If Stopped : y = ViewLine(x, y, "CPU STOPPED: opcode $" + Hex2(BadOpcode) + " at $" + Hex4(PC), Neon_C_RedR, Neon_C_RedG, Neon_C_RedB) : EndIf
  y + Neon_S(6)
  y = ViewHead(x, y, "DISASSEMBLY")
  a = PC
  For i = 0 To 15
    If i = 0
      y = ViewLine(x, y, "> " + DisLine(a), Neon_C_GrnR, Neon_C_GrnG, Neon_C_GrnB)
    Else
      y = ViewLine(x, y, "  " + DisLine(a))
    EndIf
    a = (a + DisLength(ViewPeekByte(a))) & $FFFF
  Next
  y + Neon_S(6)
  Neon_Text(*Neon_FontSmall, x, y, "MEMORY  $" + Hex4(ViewMemPage * 256) + "   (as the CPU sees it; -- = I/O)", Neon_C_AmbR, Neon_C_AmbG, Neon_C_AmbB)
  If Btn("mem back", x + Neon_S(330), y - Neon_S(2), Neon_S(28), Neon_S(20), "<") : ViewMemPage = (ViewMemPage - 1) & 255 : EndIf
  If Btn("mem forward", x + Neon_S(362), y - Neon_S(2), Neon_S(28), Neon_S(20), ">") : ViewMemPage = (ViewMemPage + 1) & 255 : EndIf
  If Btn("mem zp", x + Neon_S(394), y - Neon_S(2), Neon_S(36), Neon_S(20), "zp") : ViewMemPage = 0 : EndIf
  If Btn("mem BASIC", x + Neon_S(434), y - Neon_S(2), Neon_S(50), Neon_S(20), "BASIC") : ViewMemPage = 8 : EndIf
  If Btn("mem PC", x + Neon_S(488), y - Neon_S(2), Neon_S(36), Neon_S(20), "PC") : ViewMemPage = PC >> 8 : EndIf
  y + GLFontLineHeight(*Neon_FontMono) + Neon_S(4)
  For i = 0 To 15
    a = ViewMemPage * 256 + i * 16
    row$ = Hex4(a) + " "
    For p = 0 To 15
      v = ViewPeek(a + p)
      If v < 0 : row$ + " --" : Else : row$ + " " + Hex2(v) : EndIf
    Next
    y = ViewLine(x, y, row$)
  Next
EndProcedure

Procedure ViewVic(x.f, y.f, w.f, h.f)
  Protected i.i, row$, mode.i, bank.i
  Neon_Panel(x, y, w, h, "VIC-II", Neon_C_VioR, Neon_C_VioG, Neon_C_VioB)
  y + Neon_S(34) : x + Neon_S(12)
  mode = ((VicReg($11) >> 4) & 6) | ((VicReg($16) >> 4) & 1)
  bank = 3 - ((CiaPra(1) | (~CiaDdra(1))) & 3)
  y = ViewLine(x, y, "raster " + Str(VicRaster) + "   compare " + Str(VicCompare) + "   " + StringField("PAL 312 lines|NTSC 263 lines", 2 - C64Pal, "|") + ", " + Str(C64CyclesPerLine) + " cycles")
  y = ViewLine(x, y, "IRQ flags $" + Hex2(VicIrqFlags) + "  mask $" + Hex2(VicIrqMask) + "   badline " + Str(VicBad) + "   display " + Str(VicDisplay) + "  VC " + Str(VicVc) + " VCBASE " + Str(VicVcBase) + " RC " + Str(VicRc))
  y = ViewLine(x, y, "mode " + StringField("text|multicolour text|bitmap|multicolour bitmap|ECM text|invalid|invalid|invalid", mode + 1, "|") + "   DEN " + Str((VicReg($11) >> 4) & 1) + "  RSEL " + Str((VicReg($11) >> 3) & 1) + "  CSEL " + Str((VicReg($16) >> 3) & 1) + "  scroll " + Str(VicReg($16) & 7) + "," + Str(VicReg($11) & 7))
  y = ViewLine(x, y, "bank " + Str(bank) + " ($" + Hex4(bank * $4000) + ")   screen $" + Hex4(bank * $4000 + ((VicReg($18) & $F0) << 6)) + "   chars $" + Hex4(bank * $4000 + ((VicReg($18) & $0E) << 10)) + "   bitmap $" + Hex4(bank * $4000 + ((VicReg($18) & 8) << 10)))
  y = ViewLine(x, y, "border " + Str(VicReg($20) & 15) + "   background " + Str(VicReg($21) & 15) + " " + Str(VicReg($22) & 15) + " " + Str(VicReg($23) & 15) + " " + Str(VicReg($24) & 15) + "   lines drawn " + Str(VicLinesDrawn))
  y + Neon_S(6)
  y = ViewHead(x, y, "SPRITES   #  X    Y    colour  on  DMA show  XE YE MC behind")
  For i = 0 To 7
    y = ViewLine(x, y, "          " + Str(i) + "  " + RSet(Str(VicReg(i * 2) | (((VicReg($10) >> i) & 1) << 8)), 3) + "  " + RSet(Str(VicReg(i * 2 + 1)), 3) + "  " + RSet(Str(VicReg($27 + i) & 15), 6) + "   " + Str((VicReg($15) >> i) & 1) + "   " + Str(SprDma(i)) + "   " + Str(SprDisp(i)) + "     " + Str((VicReg($1D) >> i) & 1) + "  " + Str((VicReg($17) >> i) & 1) + "  " + Str((VicReg($1C) >> i) & 1) + "  " + Str((VicReg($1B) >> i) & 1))
  Next
  y = ViewLine(x, y, "collisions: sprite-sprite $" + Hex2(VicSprSpr) + "   sprite-background $" + Hex2(VicSprBg))
  y + Neon_S(6)
  y = ViewHead(x, y, "REGISTERS $D000-$D02E")
  For i = 0 To 2
    row$ = "$D0" + Hex2(i * 16) + " "
    Protected k.i
    For k = 0 To 15
      If i * 16 + k <= $2E : row$ + " " + Hex2(VicReg(i * 16 + k)) : EndIf
    Next
    y = ViewLine(x, y, row$)
  Next
EndProcedure

Procedure ViewSid(x.f, y.f, w.f, h.f)
  Protected v.i, b.i, ctl.i, wave$, ph.f, mid.f, i.i, smp.i, n.i, fr.i
  Neon_Panel(x, y, w, h, "SID", Neon_C_AmbR, Neon_C_AmbG, Neon_C_AmbB)
  y + Neon_S(34) : x + Neon_S(12)
  For v = 0 To 2
    b = v * 7 : ctl = SidReg(b + 4) : wave$ = ""
    If ctl & $10 : wave$ + "tri " : EndIf
    If ctl & $20 : wave$ + "saw " : EndIf
    If ctl & $40 : wave$ + "pulse " : EndIf
    If ctl & $80 : wave$ + "noise " : EndIf
    If ctl & 2 : wave$ + "sync " : EndIf
    If ctl & 4 : wave$ + "ring " : EndIf
    If ctl & 8 : wave$ + "TEST " : EndIf
    fr = SidReg(b) | (SidReg(b + 1) << 8)
    y = ViewLine(x, y, "voice " + Str(v + 1) + "  freq $" + Hex4(fr) + " (" + StrF(fr * C64Hz / 16777216.0, 1) + " Hz)  pw $" + Hex4(SidReg(b + 2) | ((SidReg(b + 3) & 15) << 8)) + "  gate " + Str(ctl & 1) + "  " + wave$)
    y = ViewLine(x, y, "         ADSR " + Hex2(SidReg(b + 5)) + " " + Hex2(SidReg(b + 6)) + "   envelope " + RSet(Str(SidEnv(v)), 3) + "  " + StringField("attack|decay/sustain|release", SidEnvState(v) + 1, "|"))
  Next
  y + Neon_S(4)
  y = ViewLine(x, y, "filter cutoff " + Str(((SidReg($16) << 3) | (SidReg($15) & 7)) & $7FF) + "  resonance " + Str(SidReg($17) >> 4) + "  routed " + Str(SidReg($17) & 7) + "  mode " + Str((SidReg($18) >> 4) & 7) + "   volume " + Str(SidReg($18) & 15) + "   3OFF " + Str(SidReg($18) >> 7))
  y = ViewLine(x, y, "samples " + Str(SidSamples) + "   sound card: " + StringField("off|on", 1 + SoundOn, "|") + "  queued " + Str(SoundQueued) + "  underruns " + Str(SoundUnderruns) + "  muted " + Str(SoundMuted), Neon_C_DimR, Neon_C_DimG, Neon_C_DimB)
  y + Neon_S(6)
  y = ViewHead(x, y, "OUTPUT (last 1024 samples, 48 kHz)")
  ph = Neon_S(180) : mid = y + ph / 2 : n = 1024
  Neon_Box(x, y, w - Neon_S(24), ph, 0.08, 0.09, 0.10)
  Neon_Box(x, mid, w - Neon_S(24), 1, Neon_C_LineR, Neon_C_LineG, Neon_C_LineB)
  For i = 0 To n - 1 Step 2
    smp = SidPcm((SidSamples - n + i) & (#SID_RING - 1))
    Neon_Box(x + i * (w - Neon_S(24)) / n, mid - smp * (ph / 2) / 32768.0, Neon_S(2), Neon_S(2), Neon_C_AccR, Neon_C_AccG, Neon_C_AccB)
  Next
EndProcedure

Procedure ViewCia(x.f, y.f, w.f, h.f)
  Protected u.i, b.i, col.i, row$
  Neon_Panel(x, y, w, h, "CIAs", Neon_C_GrnR, Neon_C_GrnG, Neon_C_GrnB)
  y + Neon_S(34) : x + Neon_S(12)
  For u = 0 To 1
    b = u * 4
    y = ViewHead(x, y, "CIA " + Str(u + 1) + " ($D" + StringField("C|D", u + 1, "|") + "00)" + StringField("   keyboard, joysticks, IRQ|   VIC bank, serial bus, NMI", u + 1, "|"))
    y = ViewLine(x, y, "timer A " + RSet(Str(TmCount(u * 2)), 5) + " latch " + RSet(Str(TmLatch(u * 2)), 5) + "  CRA $" + Hex2(CiaCra(u)) + StringField("  stopped|  running", 1 + (CiaCra(u) & 1), "|") + StringField("| one-shot", 1 + ((CiaCra(u) >> 3) & 1), "|"))
    y = ViewLine(x, y, "timer B " + RSet(Str(TmCount(u * 2 + 1)), 5) + " latch " + RSet(Str(TmLatch(u * 2 + 1)), 5) + "  CRB $" + Hex2(CiaCrb(u)) + StringField("  stopped|  running", 1 + (CiaCrb(u) & 1), "|") + "  counts " + StringField("cycles|CNT|timer A|timer A + CNT", 1 + ((CiaCrb(u) >> 5) & 3), "|"))
    y = ViewLine(x, y, "ICR $" + Hex2(CiaIcr(u)) + "  mask $" + Hex2(CiaMask(u)) + "   PRA $" + Hex2(CiaPra(u)) + " DDRA $" + Hex2(CiaDdra(u)) + "   PRB $" + Hex2(CiaPrb(u)) + " DDRB $" + Hex2(CiaDdrb(u)))
    y = ViewLine(x, y, "TOD " + Hex2(CiaTod(b + 3) & $1F) + ":" + Hex2(CiaTod(b + 2)) + ":" + Hex2(CiaTod(b + 1)) + "." + Str(CiaTod(b)) + StringField(" am| pm", 1 + (CiaTod(b + 3) >> 7), "|") + "   alarm " + Hex2(CiaAlarm(b + 3)) + ":" + Hex2(CiaAlarm(b + 2)) + ":" + Hex2(CiaAlarm(b + 1)) + "." + Str(CiaAlarm(b)))
    y + Neon_S(8)
  Next
  y = ViewHead(x, y, "KEYBOARD MATRIX (column: rows pressed)   joystick 1 $" + Hex2(Joy1) + "  joystick 2 $" + Hex2(Joy2))
  row$ = ""
  For col = 0 To 7 : row$ + Str(col) + ":" + Hex2(KeyRows(col)) + "  " : Next
  y = ViewLine(x, y, row$)
  y = ViewLine(x, y, "next CIA event at clock " + Str(CiaNextEvent) + "   IRQ (CIA 1) " + Str(Cia1Irq) + "   NMI (CIA 2) " + Str(Cia2Nmi))
EndProcedure

Declare ViewRunTests()
Procedure ViewTests(x.f, y.f, w.f, h.f)
  Protected i.i, n.i, line$
  Neon_Panel(x, y, w, h, "Tests", Neon_C_RedR, Neon_C_RedG, Neon_C_RedB)
  y + Neon_S(34) : x + Neon_S(12)
  y = ViewLine(x, y, "Wolfgang Lorenz's test suite 2.15 on this machine (stand-in ROMs, as c64_check --bench)")
  If Btn("Run tests", x, y, Neon_S(220), Neon_S(24), "Run the CPU tests (238)") : ViewRunTests() : EndIf
  y + Neon_S(32)
  If ViewTestResult$ <> ""
    If ViewTestFailed
      y = ViewLine(x, y, ViewTestResult$, Neon_C_RedR, Neon_C_RedG, Neon_C_RedB)
    Else
      y = ViewLine(x, y, ViewTestResult$, Neon_C_GrnR, Neon_C_GrnG, Neon_C_GrnB)
    EndIf
    n = CountString(ViewTestLog$, #LF$)
    For i = 1 To n
      line$ = StringField(ViewTestLog$, i, #LF$)
      If y > h - Neon_S(20) : Break : EndIf
      y = ViewLine(x, y, line$, Neon_C_DimR, Neon_C_DimG, Neon_C_DimB)
    Next
  EndIf
EndProcedure

Declare OpenProgram(path$)
Declare InsertDisk(path$)
Procedure ViewFilesRefresh(folder$)
  Protected d.i
  If folder$ = "" : ProcedureReturn : EndIf
  ViewFolder$ = folder$
  ClearList(ViewFiles())
  d = ExamineDirectory(#PB_Any, folder$, "*.*")
  If d
    While NextDirectoryEntry(d)
      If DirectoryEntryType(d) = #PB_DirectoryEntry_File
        Select LCase(GetExtensionPart(DirectoryEntryName(d)))
          Case "prg", "d64"
            AddElement(ViewFiles()) : ViewFiles() = DirectoryEntryName(d)
        EndSelect
      EndIf
    Wend
    FinishDirectory(d)
  EndIf
  SortList(ViewFiles(), #PB_Sort_Ascending | #PB_Sort_NoCase)
  ViewFilesTop = 0
EndProcedure
Procedure ViewOpenDialog()
  Protected f$ = OpenFileRequester("Open a C64 program or disk", ViewFolder$, "C64 programs and disks (*.prg;*.d64)|*.prg;*.d64|All files|*.*", 0)
  If f$ <> "" : OpenProgram(f$) : EndIf
EndProcedure
Procedure ViewPrograms(x.f, y.f, w.f, h.f)
  Protected f$, sel.i, idx.i, rowY.f, last.i
  Neon_Panel(x, y, w, h, "Programs and disks", Neon_C_AccR, Neon_C_AccG, Neon_C_AccB)
  y + Neon_S(32) : x + Neon_S(10)
  If Btn("Open file", x, y, Neon_S(110), Neon_S(24), "Open file...") : ViewOpenDialog() : EndIf
  If Btn("Choose folder", x + Neon_S(118), y, Neon_S(120), Neon_S(24), "Choose folder...")
    f$ = PathRequester("Choose a folder of .PRG and .D64 files", ViewFolder$)
    If f$ <> "" : ViewFilesRefresh(f$) : EndIf
  EndIf
  If Btn("Swap disk", x + Neon_S(246), y, Neon_S(150), Neon_S(24), "Swap disk (no reset)...")
    f$ = OpenFileRequester("Put a disk in drive 8", ViewFolder$, "C64 disks (*.d64)|*.d64|All files|*.*", 0)
    If f$ <> "" : InsertDisk(f$) : EndIf
  EndIf
  Neon_Text(*Neon_FontSmall, x + Neon_S(404), y + Neon_S(4), Neon_FitText(*Neon_FontSmall, ViewFolder$, w - Neon_S(424)), Neon_C_DimR, Neon_C_DimG, Neon_C_DimB)
  y + Neon_S(32)
  Neon_ListBegin(7, x, y, w - Neon_S(20), h - Neon_S(76), Neon_S(22), @ViewFilesTop)
  last = Neon_ListTop + Int(Neon_ListH / Neon_ListRowH) - 1
  ForEach ViewFiles()
    idx = Neon_ListRow : rowY = Neon_ListY + (idx - Neon_ListTop) * Neon_ListRowH
    If idx = Neon_ListTop : CtlSet("list first row", Neon_ListX, rowY, Neon_ListW - Neon_S(10), Neon_ListRowH) : EndIf
    If idx = last : CtlSet("list last row", Neon_ListX, rowY, Neon_ListW - Neon_S(10), Neon_ListRowH) : EndIf
    sel = Bool(ViewFolder$ + ViewFiles() = ViewCurrent$)
    If Neon_ListItem(ViewFiles(), 0, sel)
      If PtOn
        PtClicked$ = "list row " + Str(idx)
        If idx = Neon_ListTop : PtClicked$ = "list first row" : EndIf
        If idx = last : PtClicked$ = "list last row" : EndIf
      Else
        OpenProgram(ViewFolder$ + ViewFiles())
      EndIf
    EndIf
  Next
  Neon_ListEnd()
EndProcedure

Procedure ViewDrawPanel(tab.i, x.f, y.f, w.f, h.f)
  Select tab
    Case 0 : ViewCpu(x, y, w, h)
    Case 1 : ViewVic(x, y, w, h)
    Case 2 : ViewSid(x, y, w, h)
    Case 3 : ViewCia(x, y, w, h)
    Case 4 : ViewTests(x, y, w, h)
    Case 5 : ViewPrograms(x, y, w, h)
  EndSelect
EndProcedure

DataSection
ViewPalette:
  ; the VIC-II's 16 colours (Pepto's PAL measurements), as on the boards
  Data.a $00,$00,$00, $FF,$FF,$FF, $68,$37,$2B, $70,$A4,$B2, $6F,$3D,$86, $58,$8D,$43, $35,$28,$79, $B8,$C7,$6F
  Data.a $6F,$4F,$25, $43,$39,$00, $9A,$67,$59, $44,$44,$44, $6C,$6C,$6C, $9A,$D2,$84, $6C,$5E,$B5, $95,$95,$95
EndDataSection
