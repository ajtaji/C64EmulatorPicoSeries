; The PC keyboard as the C64's 8 x 8 matrix, the joystick on the PC's keys, and RESTORE - all from the
; one table in controls.pbi (which the Controls tab and the README show too). Keys are the engine's
; codes (#PB_Shortcut_ / #GL_Key_: virtual keys on Windows, X keysyms on Linux), read through it.
EnableExplicit
XIncludeFile "controls.pbi"
Structure KbKey
  vk.i
  k.i                            ; C64 key (col * 8 + row), +64 = with SHIFT
  joy.i                          ; the joystick key with this code (with the joystick keys on it wins), 0 none
EndStructure
Global NewList KbKeys.KbKey()
Global NewList KbJoy.KbKey()     ; the joystick keys: vk and the joystick bit (in joy)
Global KbJoyKeys.i = 1, KbJoyPort.i = 2
Global KbRestoreHeld.i
Global KbRestoreVk.i = #PB_Shortcut_PageUp
Global KbNoEsc.i                 ; 1 in full screen: Esc leaves it, the C64 does not see it
Global KbTestKey.i = -1          ; --fullscreen-test: the one key held (no real keyboard read), -1 off

Procedure KbInit()
  ControlsInit()
  ClearList(KbKeys()) : ClearList(KbJoy())
  ForEach Controls()
    Select Controls()\kind
      Case #CTL_JOY : AddElement(KbJoy()) : KbJoy()\vk = Controls()\vk : KbJoy()\joy = Controls()\col
      Case #CTL_RESTORE : KbRestoreVk = Controls()\vk
    EndSelect
  Next
  ForEach Controls()
    If Controls()\kind = #CTL_KEY
      AddElement(KbKeys()) : KbKeys()\vk = Controls()\vk : KbKeys()\k = Controls()\col * 8 + Controls()\row + Controls()\shift * 64
      ForEach KbJoy()
        If KbJoy()\vk = KbKeys()\vk : KbKeys()\joy = KbJoy()\joy : EndIf
      Next
    EndIf
  Next
EndProcedure

; The whole keyboard read once a frame (the engine's GL_KeysSnapshot), then each key from that read.
Procedure.i KbDown(vk.i)
  If KbTestKey >= 0 : ProcedureReturn Bool(vk = KbTestKey) : EndIf
  ProcedureReturn GL_KeySnap(vk)
EndProcedure

; The matrix and the joystick from the keys held now (only while the window has focus).
; Returns the joystick bits (up 1, down 2, left 4, right 8, fire 16).
Procedure.i KbApply(active.i)
  Protected k.i, col.i, row.i, shift.i, joy.i
  For col = 0 To 7 : KeyRows(col) = 0 : Next
  If active = 0 : KbRestoreHeld = 0 : ProcedureReturn 0 : EndIf
  If KbTestKey < 0 : GL_KeysSnapshot() : EndIf
  ; a joystick key (with the joystick keys on) is the joystick's, not the keyboard's
  If KbJoyKeys
    ForEach KbJoy()
      If KbDown(KbJoy()\vk) : joy | KbJoy()\joy : EndIf
    Next
  EndIf
  ForEach KbKeys()
    If KbJoyKeys And KbKeys()\joy : Continue : EndIf
    If KbNoEsc And KbKeys()\vk = #PB_Shortcut_Escape : Continue : EndIf
    If KbDown(KbKeys()\vk)
      k = KbKeys()\k : col = (k >> 3) & 7 : row = k & 7
      KeyRows(col) | (1 << row)
      If k & 64 : shift = 1 : EndIf
    EndIf
  Next
  If shift : KeyRows(1) | (1 << 7) : EndIf
  ; RESTORE is wired to the NMI line, not the matrix
  KbRestoreHeld = KbDown(KbRestoreVk)
  ProcedureReturn joy
EndProcedure
