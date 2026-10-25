; Wolfgang Lorenz's 6510 test suite on the desktop core, in Christer Palm's
; test bench: flat 64 KB RAM, traps at $FFD2 (print), $E16F (load the next
; test), $FFE4 (a key: a failed test waits here), $8000 / $A474 (exit).
; Runs from " start" through every CPU test until the chain asks for trap17.
;
;   lorenz_check.exe [first-test] [--one]
EnableExplicit
CompilerIf Defined(PROCS, #PB_Constant)
  XIncludeFile "core/cpu6510_procs.pbi"
CompilerElse
  XIncludeFile "core/cpu6510.pbi"
CompilerEndIf

Global TestDir$ = GetPathPart(ProgramFilename()) + "..\tests\lorenz\"
Global Prints.i, Line$, Failures.i, Tests.i, Finished.i, One.i, Current$
Global Dim FlatPages.i(0)

Procedure.i C64IoRead(addr.i)
  ProcedureReturn M(addr & $FFFF)
EndProcedure
Procedure C64IoWrite(addr.i, v.i)
  M(addr & $FFFF) = v
EndProcedure
Procedure C64PortWrite(addr.i, v.i)
  M(addr) = v
EndProcedure

Procedure.i LoadTest(name$)
  Protected f.i, size.i, addr.i, *buf, i.i
  f = ReadFile(#PB_Any, TestDir$ + name$)
  If f = 0
    PrintN("") : PrintN("MISSING TEST FILE: " + name$) : Failures + 1 : ProcedureReturn 0
  EndIf
  size = Lof(f)
  *buf = AllocateMemory(size)
  ReadData(f, *buf, size) : CloseFile(f)
  addr = PeekA(*buf) | (PeekA(*buf + 1) << 8)
  For i = 2 To size - 1
    M((addr + i - 2) & $FFFF) = PeekA(*buf + i)
  Next
  FreeMemory(*buf)
  M($0002) = $00 : M($A002) = $00 : M($A003) = $80
  M($FFFE) = $48 : M($FFFF) = $FF : M($01FE) = $FF : M($01FF) = $7F
  ; the IRQ / BRK entry: a trap (C64Trap)
  M($FF48) = $02
  M($FFD2) = $02 : M($E16F) = $02 : M($FFE4) = $02 : M($8000) = $02 : M($A474) = $02
  Tests + 1 : Current$ = name$
  If Tests = 123 Or Tests = 145 : PrintN("") : PrintN("INSTR_AT_" + Str(Tests) + " " + Str(CpuInstructions)) : EndIf
  ProcedureReturn 1
EndProcedure

Procedure.s Petscii(c.i)
  If c = 13 : ProcedureReturn #LF$ : EndIf
  If c >= 65 And c <= 90 : ProcedureReturn Chr(c + 32) : EndIf
  If c >= 193 And c <= 218 : ProcedureReturn Chr(c - 128) : EndIf
  If c >= 32 And c < 127 : ProcedureReturn Chr(c) : EndIf
  ProcedureReturn ""
EndProcedure

Procedure Rts()
  CpuPop(Lo) : CpuPop(Hi)
  PC = ((Lo | (Hi << 8)) + 1) & $FFFF
EndProcedure

Procedure.i C64Trap(addr.i)
  Protected name$, i.i, c.i
  Select addr
    Case $FF48
      ; the IRQ / BRK entry a KERNAL has, done here (no ROM code): A, X, Y saved; the status the
      ; interrupt pushed says BRK ($0316) or IRQ ($0314); the cycles its code takes (29, the trap's 2 counted)
      CpuPush(A) : CpuPush(X) : CpuPush(Y)
      c = $0314
      Left - 27
      If M($100 + ((S + 4) & 255)) & $10 : c = $0316 : Left + 1 : EndIf
      PC = M(c) | (M(c + 1) << 8)
      ProcedureReturn 1
    Case $FFD2
      M($030C) = 0 : Prints + 1
      c = A
      If c = 13
        Print(#LF$)
      Else
        Print(Petscii(c))
      EndIf
      Rts()
    Case $E16F
      For i = 0 To M($B7) - 1
        c = M((M($BB) | (M($BC) << 8)) + i)
        If c >= 65 And c <= 90 : c + 32 : EndIf
        name$ + Chr(c)
      Next
      If name$ = "trap17" Or One
        Finished = 1 : Stopped = 1
      ElseIf LoadTest(name$) = 0
        Stopped = 1
      Else
        CpuPop(Lo) : CpuPop(Hi)
        PC = $0816
      EndIf
    Case $FFE4
      Failures + 1
      PrintN("") : PrintN("*** FAILED: " + Current$)
      A = 3
      Rts()
    Case $8000, $A474
      Finished = 1 : Stopped = 1
    Default
      ProcedureReturn 0
  EndSelect
  ProcedureReturn 1
EndProcedure

Define i.i, first$ = " start", t.q, cycles.q, arg$
For i = 0 To CountProgramParameters() - 1
  arg$ = ProgramParameter(i)
  If arg$ = "--one" : One = 1 : Else : first$ = arg$ : EndIf
Next
OpenConsole()
For i = 0 To 255
  RdMap(i) = @M(0) : WrMap(i) = @M(0)
Next
LoadTest(first$)
S = $FD : CpuSetStatus($04) : PC = $0801
t = ElapsedMilliseconds()
While Stopped = 0
  cycles + CpuRun(100000)
Wend
t = ElapsedMilliseconds() - t
PrintN("")
If Stopped And Finished = 0
  PrintN("CPU STOPPED at $" + Hex(PC) + " opcode $" + Hex(BadOpcode) + " in " + Current$) : Failures + 1
EndIf
PrintN("LORENZ prints=" + Str(Prints) + " tests=" + Str(Tests) + " failures=" + Str(Failures) + " cycles=" + Str(cycles) + " instructions=" + Str(CpuInstructions) + " ms=" + Str(t))
If t > 0 : PrintN("speed " + StrF(CpuInstructions / t / 1000.0, 1) + " M instructions/s") : EndIf
If Failures : End 1 : EndIf
End 0

