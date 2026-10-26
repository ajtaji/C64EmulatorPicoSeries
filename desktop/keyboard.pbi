; The PC keyboard as the C64's 8 x 8 matrix, the joystick on the PC's keys, and RESTORE - all from the
; one table in controls.pbi (which the Controls tab and the README show too).
EnableExplicit
XIncludeFile "controls.pbi"
Global Dim KbMap.i(256)          ; PC key -> C64 key (col * 8 + row), -1 none; +64 = with SHIFT
Global KbJoyKeys.i = 1, KbJoyPort.i = 2
Global KbRestoreHeld.i
Global Dim KbJoyBit.i(256)       ; PC key -> joystick bit (with the joystick keys on), 0 none
Global KbRestoreVk.i = #PB_Shortcut_PageUp
Global KbNoEsc.i                 ; 1 in full screen: Esc leaves it, the C64 does not see it

Procedure KbSet(pc.i, col.i, row.i, shift.i = 0)
  KbMap(pc) = col * 8 + row + shift * 64
EndProcedure

Procedure KbInit()
  Protected i.i
  ControlsInit()
  For i = 0 To 255 : KbMap(i) = -1 : KbJoyBit(i) = 0 : Next
  ForEach Controls()
    Select Controls()\kind
      Case #CTL_KEY : KbSet(Controls()\vk, Controls()\col, Controls()\row, Controls()\shift)
      Case #CTL_JOY : KbJoyBit(Controls()\vk & 255) = Controls()\col
      Case #CTL_RESTORE : KbRestoreVk = Controls()\vk
    EndSelect
  Next
EndProcedure

; The whole keyboard read once a frame (GetKeyboardState: the state this thread's message queue has
; reached, which the main loop drains every pass). GetAsyncKeyState a key at a time cost ~200 us a
; call on this PC - 14 ms a frame for the ~70 keys, the emulator then at 9-16 frames/s.
Global Dim KbState.a(255)
Procedure.i KbDown(vk.i)
  ProcedureReturn Bool(KbState(vk & 255) & $80)
EndProcedure

; The matrix and the joystick from the keys held now (only while the window has focus).
; Returns the joystick bits (up 1, down 2, left 4, right 8, fire 16).
Procedure.i KbApply(active.i)
  Protected vk.i, k.i, col.i, row.i, shift.i, joy.i
  For col = 0 To 7 : KeyRows(col) = 0 : Next
  If active = 0 : KbRestoreHeld = 0 : ProcedureReturn 0 : EndIf
  CompilerIf #PB_Compiler_OS = #PB_OS_Windows
    GetKeyboardState_(@KbState(0))
  CompilerEndIf
  For vk = 8 To 254
    ; a joystick key (with the joystick keys on) is the joystick's, not the keyboard's
    If KbJoyKeys And KbJoyBit(vk)
      If KbDown(vk) : joy | KbJoyBit(vk) : EndIf
      Continue
    EndIf
    k = KbMap(vk)
    If k >= 0 And vk <> #VK_SHIFT And vk <> #VK_CONTROL
      If KbNoEsc And vk = #VK_ESCAPE : Continue : EndIf
      If KbDown(vk)
        col = (k >> 3) & 7 : row = k & 7
        KeyRows(col) | (1 << row)
        If k & 64 : shift = 1 : EndIf
      EndIf
    EndIf
  Next
  If shift : KeyRows(1) | (1 << 7) : EndIf
  ; RESTORE is wired to the NMI line, not the matrix
  KbRestoreHeld = KbDown(KbRestoreVk)
  ProcedureReturn joy
EndProcedure
