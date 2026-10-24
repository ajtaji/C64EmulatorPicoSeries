; The desktop machine's console check.
;
;   c64_check.exe --bench [first-test]   Lorenz's suite on the whole machine
;                                         (stand-in ROMs; CPU, CIA, IRQ, timing)
;   c64_check.exe --boot <romdir> [--frames N] [--prg file] [--d64 file] [--type "text"] [--shot out.bmp]
;                                         boot BASIC with real ROMs, optionally load and type
EnableExplicit
XIncludeFile "core/machine.pbi"

Global TestDir$ = GetPathPart(ProgramFilename()) + "..\tests\lorenz\"
Global *BenchRec, BenchOut$, BenchLine$
Global Dim Frame.a(384 * 272)
Global FramesDone.i

Procedure.i PlatformLine(viewY.i)
  ProcedureReturn @Frame(viewY * 384)
EndProcedure
Procedure PlatformLineDone(viewY.i)
EndProcedure
Procedure PlatformTick()
EndProcedure
Procedure PlatformFrameDone()
  FramesDone + 1
EndProcedure

Procedure.i BenchFile(nameAdr.i, n.i)
  Protected name$, f.i, size.i, i.i
  For i = 0 To n - 1 : name$ + Chr(PeekA(nameAdr + i)) : Next
  If name$ = "" : ProcedureReturn 0 : EndIf
  f = ReadFile(#PB_Any, TestDir$ + name$)
  If f = 0 : ProcedureReturn 0 : EndIf
  size = Lof(f)
  If *BenchRec : FreeMemory(*BenchRec) : EndIf
  *BenchRec = AllocateMemory(size + n + 3)
  PokeA(*BenchRec, n)
  For i = 0 To n - 1 : PokeA(*BenchRec + 1 + i, PeekA(nameAdr + i)) : Next
  PokeA(*BenchRec + 1 + n, size & 255) : PokeA(*BenchRec + 2 + n, size >> 8)
  ReadData(f, *BenchRec + 3 + n, size)
  CloseFile(f)
  ProcedureReturn *BenchRec
EndProcedure

Procedure BenchPrint(c.i)
  If c = 13
    PrintN(BenchLine$) : BenchLine$ = ""
  ElseIf c >= 65 And c <= 90
    BenchLine$ + Chr(c + 32)
  ElseIf c >= 193 And c <= 218
    BenchLine$ + Chr(c - 128)
  ElseIf c >= 32 And c < 127
    BenchLine$ + Chr(c)
  EndIf
EndProcedure

Procedure.s RecName(rec.i)
  Protected i.i, s$
  For i = 1 To PeekA(rec) : s$ + Chr(PeekA(rec + i)) : Next
  ProcedureReturn s$
EndProcedure

Global BenchOne.i
Procedure BenchEvent(kind.i, rec.i)
  If kind = 1 And BenchOne And BenchTests > 1
    BenchFinished = 1 : Stopped = 1
  EndIf
  If kind = 2
    PrintN("") : PrintN("BENCH_NEXT " + PeekS(@BenchName(0), BenchNameLen, #PB_Ascii) + " (b7=" + Str(M($B7)) + " bb=$" + Hex(M($BB) | (M($BC) << 8)) + " ret=$" + Hex(M($101 + S) | (M($102 + S) << 8)) + " line=" + BenchLine$ + ")")
  ElseIf kind = 3
    PrintN(BenchLine$) : BenchLine$ = ""
    PrintN("*** FAILED: " + RecName(rec))
  EndIf
EndProcedure

Procedure.i LoadFile(path$, *size.Integer)
  Protected f.i, *m
  f = ReadFile(#PB_Any, path$)
  If f = 0 : PrintN("cannot open " + path$) : End 2 : EndIf
  *size\i = Lof(f)
  *m = AllocateMemory(*size\i + 16)
  ReadData(f, *m, *size\i) : CloseFile(f)
  ProcedureReturn *m
EndProcedure

; The screen's text (40 x 25 at the matrix base) as ASCII, for the log.
Procedure.s ScreenText()
  Protected r.i, c.i, ch.i, s$, row$, base.i
  base = ((VicReg($18) & $F0) << 6) + (3 - ((CiaPra(1) | (~CiaDdra(1))) & 3)) * $4000
  For r = 0 To 24
    row$ = ""
    For c = 0 To 39
      ch = M(base + r * 40 + c) & 127
      If ch < 32 : ch + 64 : ElseIf ch >= 64 And ch < 96 : ch + 32 : EndIf
      row$ + Chr(ch)
    Next
    s$ + RTrim(row$) + #LF$
  Next
  ProcedureReturn s$
EndProcedure

Procedure SaveShot(path$)
  Protected img.i, px.i, py.i, c.i
  img = CreateImage(#PB_Any, 384, 272, 24)
  StartDrawing(ImageOutput(img))
  For py = 0 To 271
    For px = 0 To 383
      c = Frame(py * 384 + px) & 15
      Plot(px, py, RGB(PeekA(?Pal + c * 3), PeekA(?Pal + c * 3 + 1), PeekA(?Pal + c * 3 + 2)))
    Next
  Next
  StopDrawing()
  SaveImage(img, path$, #PB_ImagePlugin_BMP)
EndProcedure

Define wav$, i.i, arg$, mode$, first$ = " start", romdir$, frames.i = 100000, prg$, d64$, type$, shot$
Define t.q, cyc.q, size.i, *basic, *kernal, *chars, *prg, *d64, st.i
OpenConsole()
For i = 0 To CountProgramParameters() - 1
  arg$ = ProgramParameter(i)
  Select arg$
    Case "--bench" : mode$ = "bench"
      If i + 1 < CountProgramParameters() And Left(ProgramParameter(i + 1), 2) <> "--" : i + 1 : first$ = ProgramParameter(i) : EndIf
    Case "--boot" : mode$ = "boot" : i + 1 : romdir$ = ProgramParameter(i)
    Case "--frames" : i + 1 : frames = Val(ProgramParameter(i))
    Case "--prg" : i + 1 : prg$ = ProgramParameter(i)
    Case "--d64" : i + 1 : d64$ = ProgramParameter(i)
    Case "--type" : i + 1 : type$ = ProgramParameter(i)
    Case "--shot" : i + 1 : shot$ = ProgramParameter(i)
    Case "--wav" : i + 1 : wav$ = ProgramParameter(i)
    Case "--ntsc" : C64SetStandard(0)
    Case "--demo" : mode$ = "demo"

    Case "--one" : BenchOne = 1
    Case "--roms" : i + 1 : romdir$ = ProgramParameter(i)
  EndSelect
Next

If mode$ = "bench"
  If romdir$
    Define bd.i, bn$, bsz.i
    If Right(romdir$, 1) <> "\" : romdir$ + "\" : EndIf
    bd = ExamineDirectory(#PB_Any, romdir$, "*.*")
    While bd And NextDirectoryEntry(bd)
      bn$ = LCase(DirectoryEntryName(bd)) : bsz = DirectoryEntrySize(bd)
      If bsz = 8192 And FindString(bn$, "basic") : *basic = LoadFile(romdir$ + DirectoryEntryName(bd), @size) : EndIf
      If bsz = 8192 And FindString(bn$, "kernal") : *kernal = LoadFile(romdir$ + DirectoryEntryName(bd), @size) : EndIf
      If bsz = 4096 And FindString(bn$, "char") : *chars = LoadFile(romdir$ + DirectoryEntryName(bd), @size) : EndIf
    Wend
    If *basic And *kernal And *chars : C64SetRoms(*basic, *kernal, *chars) : BenchKeepRoms = 1 : EndIf
  EndIf
  Define *nm = AllocateMemory(64)
  PokeS(*nm, first$, -1, #PB_Ascii)
  If BenchStart(*nm, Len(first$)) = 0 : PrintN("no test " + first$) : End 2 : EndIf
  t = ElapsedMilliseconds()
  While Stopped = 0 And FramesDone < frames
    C64RunFrame()
  Wend
  If Stopped = 0 : PrintN(BenchLine$) : PrintN("*** TIMEOUT after " + Str(frames) + " frames in " + RecName(BenchCurrent) + " pc=$" + Hex(PC) + " i=" + Str(FI)) : BenchFailures + 1 : BenchFinished = 1 : EndIf
  t = ElapsedMilliseconds() - t
  If BenchFinished = 0
    PrintN("") : PrintN("CPU STOPPED at $" + Hex(PC) + " opcode $" + Hex(BadOpcode) + " in " + RecName(BenchCurrent))
    BenchFailures + 1
  EndIf
  PrintN("BENCH tests=" + Str(BenchTests) + " failures=" + Str(BenchFailures) + " frames=" + Str(FramesDone) + " ms=" + Str(t) + " instructions=" + Str(CpuInstructions))
  If BenchFailures : End 1 : EndIf
  End 0
EndIf

If mode$ = "demo"
  *prg = LoadFile(GetPathPart(ProgramFilename()) + "..\tests\demo.prg", @size)
  BenchRoms() : BenchMode = 0
  C64PowerOn()
  C64InjectPrg(*prg, size, 0)
  PC = $C000
  Define peak.i, k.i
  Define wavf.i, cur.i
  If wav$ : wavf = CreateFile(#PB_Any, wav$) : WriteData(wavf, ?WavHead, 44) : EndIf
  cur = SidSamples
  t = ElapsedMilliseconds()
  For i = 1 To frames
    C64RunFrame()
    If wavf
      While cur < SidSamples : WriteWord(wavf, SidPcm(cur & (#SID_RING - 1))) : cur + 1 : Wend
    EndIf
  Next
  t = ElapsedMilliseconds() - t
  If wavf
    FileSeek(wavf, 40) : WriteLong(wavf, (cur - 0) * 2) : FileSeek(wavf, 4) : WriteLong(wavf, 36 + cur * 2) : CloseFile(wavf)
  EndIf
  For k = 0 To #SID_RING - 1
    If Abs(SidPcm(k)) > peak : peak = Abs(SidPcm(k)) : EndIf
  Next
  PrintN("DEMO frames=" + Str(frames) + " ms=" + Str(t) + " instructions=" + Str(CpuInstructions) + " pc=$" + Hex(PC) + " stopped=" + Str(Stopped) + " raster_irqs_flag=" + Str(VicIrqFlags) + " sid_samples=" + Str(SidSamples) + " sid_peak=" + Str(peak))
  If shot$ : SaveShot(shot$) : EndIf
  End 0
EndIf

If mode$ = "boot"
  Define dd.i, n$, sz.i
  If Right(romdir$, 1) <> "\" : romdir$ + "\" : EndIf
  dd = ExamineDirectory(#PB_Any, romdir$, "*.*")
  If dd
    While NextDirectoryEntry(dd)
      n$ = LCase(DirectoryEntryName(dd)) : sz = DirectoryEntrySize(dd)
      If sz = 8192 And FindString(n$, "basic") : *basic = LoadFile(romdir$ + DirectoryEntryName(dd), @size) : EndIf
      If sz = 8192 And FindString(n$, "kernal") : *kernal = LoadFile(romdir$ + DirectoryEntryName(dd), @size) : EndIf
      If sz = 4096 And (FindString(n$, "char") Or FindString(n$, "901225")) : *chars = LoadFile(romdir$ + DirectoryEntryName(dd), @size) : EndIf
    Wend
    FinishDirectory(dd)
  EndIf
  If *basic = 0 Or *kernal = 0 Or *chars = 0 : PrintN("ROMs not found in " + romdir$) : End 2 : EndIf
  C64SetRoms(*basic, *kernal, *chars)
  C64PowerOn()
  If d64$ : *d64 = LoadFile(d64$, @size) : C64InsertD64(*d64, size) : EndIf
  If prg$ : *prg = LoadFile(prg$, @size) : C64QueuePrg(*prg, size, 1) : EndIf
  If type$
    Define *tx = AllocateMemory(Len(type$) + 2)
    PokeS(*tx, ReplaceString(type$, "\n", #LF$), -1, #PB_Ascii)
    C64TypeText(*tx)
  EndIf
  t = ElapsedMilliseconds()
  For i = 1 To frames
    C64LoaderFrame()
    C64RunFrame()
  Next
  t = ElapsedMilliseconds() - t
  Print(ScreenText())
  PrintN("BOOT frames=" + Str(frames) + " ms=" + Str(t) + " instructions=" + Str(CpuInstructions) + " pc=$" + Hex(PC) + " stopped=" + Str(Stopped) + " loads=" + Str(LoadCount) + " sid_samples=" + Str(SidSamples))
  If shot$ : SaveShot(shot$) : EndIf
  End 0
EndIf
PrintN("usage: c64_check --bench [test] | --boot <romdir> [--frames N] [--prg f] [--d64 f] [--type text] [--shot f.bmp]")
End 2

DataSection
WavHead:
  Data.a $52,$49,$46,$46, 0,0,0,0, $57,$41,$56,$45, $66,$6D,$74,$20, 16,0,0,0, 1,0, 1,0, $80,$BB,0,0, 0,$77,1,0, 2,0, 16,0, $64,$61,$74,$61, 0,0,0,0
Pal:
  ; the VIC-II's 16 colours (Pepto's PAL measurements)
  Data.a $00,$00,$00, $FF,$FF,$FF, $68,$37,$2B, $70,$A4,$B2, $6F,$3D,$86, $58,$8D,$43, $35,$28,$79, $B8,$C7,$6F
  Data.a $6F,$4F,$25, $43,$39,$00, $9A,$67,$59, $44,$44,$44, $6C,$6C,$6C, $9A,$D2,$84, $6C,$5E,$B5, $95,$95,$95
EndDataSection
