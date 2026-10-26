; THE CONTROLS: one table that the keyboard code (keyboard.pbi), the window's shortcuts, the Controls tab
; (view.pbi) and the README's Controls section (tools/controls_readme.py) all read - so they cannot disagree.
;
; A row: kind, PC key (a virtual-key code), what the PC key is called, what it is on the C64, and for a
; C64 key its place in the 8 x 8 matrix (column, row) and whether SHIFT goes with it. Rows marked hidden
; are read by the keyboard code but shown as one summary row in the Controls tab.
;
; Esc: in the window Esc is RUN/STOP (as on most C64 emulators); in full screen Esc leaves full screen and
; is not passed to the C64 - End is RUN/STOP there (and always).
EnableExplicit

#CTL_KEY = 0          ; a C64 key
#CTL_RESTORE = 1      ; RESTORE (the NMI line, not the matrix)
#CTL_JOY = 2          ; a joystick direction or fire (col = the joystick bit), with the joystick keys on
#CTL_PAD = 3          ; the gamepad (a note: the code reads the first gamepad's stick and buttons 1 and 2)
#CTL_SHORTCUT = 4     ; the window's own (col = the action)
#CTL_NOTE = 5         ; a summary row of the Controls tab only

#ACT_RUNPAUSE = 1
#ACT_STEP = 2
#ACT_FRAME = 3
#ACT_RESET = 4
#ACT_FULLSCREEN = 5
#ACT_LEAVEFULL = 6

Structure CtlRow
  kind.i
  vk.i
  pc$
  c64$
  col.i
  row.i
  shift.i
  hidden.i
EndStructure
Global NewList Controls.CtlRow()
Global Controls_c.i, Controls_r.i

Procedure CtlAdd(kind.i, vk.i, pc$, c64$, col.i = 0, row.i = 0, shift.i = 0, hidden.i = 0)
  AddElement(Controls())
  Controls()\kind = kind : Controls()\vk = vk : Controls()\pc$ = pc$ : Controls()\c64$ = c64$
  Controls()\col = col : Controls()\row = row : Controls()\shift = shift : Controls()\hidden = hidden
EndProcedure

Procedure ControlsInit()
  Protected i.i, c$
  ClearList(Controls())
  ; letters and digits by position (hidden: one summary row)
  CtlAdd(#CTL_NOTE, 0, "A-Z, 0-9, Space, Return", "the same keys")
  Restore CtlLetters
  For i = 0 To 25
    Read.s c$ : Read.i Controls_c : Read.i Controls_r
    CtlAdd(#CTL_KEY, #PB_Shortcut_A + i, c$, c$, Controls_c, Controls_r, 0, 1)
  Next
  Restore CtlDigits
  For i = 0 To 9
    Read.i Controls_c : Read.i Controls_r
    CtlAdd(#CTL_KEY, #PB_Shortcut_0 + i, Str(i), Str(i), Controls_c, Controls_r, 0, 1)
  Next
  CtlAdd(#CTL_KEY, #PB_Shortcut_Space, "Space", "SPACE", 7, 4, 0, 1)
  CtlAdd(#CTL_KEY, #PB_Shortcut_Return, "Return", "RETURN", 0, 1, 0, 1)
  ; the keys that differ
  CtlAdd(#CTL_KEY, #PB_Shortcut_Escape, "Esc (in the window)", "RUN/STOP", 7, 7)
  CtlAdd(#CTL_KEY, #PB_Shortcut_End, "End", "RUN/STOP", 7, 7)
  CtlAdd(#CTL_RESTORE, #PB_Shortcut_PageUp, "Page Up", "RESTORE")
  CtlAdd(#CTL_KEY, #VK_LCONTROL, "Left Ctrl", "C= (Commodore)", 7, 5)
  CtlAdd(#CTL_KEY, #PB_Shortcut_Tab, "Tab", "CTRL", 7, 2)
  CtlAdd(#CTL_KEY, #VK_LSHIFT, "Left Shift", "LEFT SHIFT", 1, 7)
  CtlAdd(#CTL_KEY, #VK_RSHIFT, "Right Shift", "RIGHT SHIFT", 6, 4)
  CtlAdd(#CTL_KEY, #PB_Shortcut_Home, "Home", "CLR/HOME", 6, 3)
  CtlAdd(#CTL_KEY, #PB_Shortcut_Back, "Backspace", "INST/DEL", 0, 0)
  CtlAdd(#CTL_KEY, #PB_Shortcut_Insert, "Insert", "+", 5, 0)
  CtlAdd(#CTL_KEY, #PB_Shortcut_Delete, "Delete", "up arrow", 6, 6)
  CtlAdd(#CTL_KEY, #PB_Shortcut_Right, "Right (joystick keys off)", "CRSR right", 0, 2)
  CtlAdd(#CTL_KEY, #PB_Shortcut_Left, "Left (joystick keys off)", "CRSR left (SHIFT + CRSR right)", 0, 2, 1)
  CtlAdd(#CTL_KEY, #PB_Shortcut_Down, "Down (joystick keys off)", "CRSR down", 0, 7)
  CtlAdd(#CTL_KEY, #PB_Shortcut_Up, "Up (joystick keys off)", "CRSR up (SHIFT + CRSR down)", 0, 7, 1)
  CtlAdd(#CTL_KEY, #PB_Shortcut_F1, "F1", "f1", 0, 4)
  CtlAdd(#CTL_KEY, #PB_Shortcut_F2, "F2", "f2 (SHIFT + f1)", 0, 4, 1)
  CtlAdd(#CTL_KEY, #PB_Shortcut_F3, "F3", "f3", 0, 5)
  CtlAdd(#CTL_KEY, #PB_Shortcut_F4, "F4", "f4 (SHIFT + f3)", 0, 5, 1)
  CtlAdd(#CTL_KEY, #PB_Shortcut_Pad5, "Keypad 5", "f5", 0, 6)
  CtlAdd(#CTL_KEY, #PB_Shortcut_Pad7, "Keypad 7", "f7", 0, 3)
  CtlAdd(#CTL_KEY, #VK_OEM_MINUS, "-", "+", 5, 3)
  CtlAdd(#CTL_KEY, #VK_OEM_PLUS, "=", "-", 6, 5)
  CtlAdd(#CTL_KEY, #VK_OEM_4, "[", "@", 5, 6)
  CtlAdd(#CTL_KEY, #VK_OEM_6, "]", "*", 6, 1)
  CtlAdd(#CTL_KEY, #VK_OEM_1, ";", ":", 5, 5)
  CtlAdd(#CTL_KEY, #VK_OEM_7, "'", ";", 6, 2)
  CtlAdd(#CTL_KEY, #VK_OEM_COMMA, ",", ",", 5, 7)
  CtlAdd(#CTL_KEY, #VK_OEM_PERIOD, ".", ".", 5, 4)
  CtlAdd(#CTL_KEY, #VK_OEM_2, "/", "/", 6, 7)
  CtlAdd(#CTL_KEY, #VK_OEM_5, "\", "pound", 6, 0)
  CtlAdd(#CTL_KEY, #VK_OEM_3, "`", "left arrow", 7, 1)
  ; the joystick (in port 2, or 1 - the toolbar's Joy keys button), on the PC's keys and the first gamepad
  CtlAdd(#CTL_JOY, #VK_UP, "Up", "joystick up", 1)
  CtlAdd(#CTL_JOY, #VK_DOWN, "Down", "joystick down", 2)
  CtlAdd(#CTL_JOY, #VK_LEFT, "Left", "joystick left", 4)
  CtlAdd(#CTL_JOY, #VK_RIGHT, "Right", "joystick right", 8)
  CtlAdd(#CTL_JOY, #VK_RCONTROL, "Right Ctrl", "joystick fire", 16)
  CtlAdd(#CTL_JOY, #VK_RMENU, "Right Alt", "joystick fire", 16)
  CtlAdd(#CTL_PAD, 0, "Gamepad stick / d-pad", "joystick directions")
  CtlAdd(#CTL_PAD, 0, "Gamepad button 1 or 2", "joystick fire")
  ; the window's own
  CtlAdd(#CTL_SHORTCUT, #PB_Shortcut_F5, "F5", "run / pause", #ACT_RUNPAUSE)
  CtlAdd(#CTL_SHORTCUT, #PB_Shortcut_F6, "F6", "step one instruction", #ACT_STEP)
  CtlAdd(#CTL_SHORTCUT, #PB_Shortcut_F7, "F7", "step one frame", #ACT_FRAME)
  CtlAdd(#CTL_SHORTCUT, #PB_Shortcut_F8, "F8", "reset", #ACT_RESET)
  CtlAdd(#CTL_SHORTCUT, #PB_Shortcut_F11, "F11", "full screen on / off", #ACT_FULLSCREEN)
  CtlAdd(#CTL_SHORTCUT, #PB_Shortcut_Escape, "Esc (in full screen)", "leave full screen", #ACT_LEAVEFULL)
EndProcedure
; The shortcut a key is in the window (full screen or not), or 0.
Procedure.i ControlsAction(vk.i, fullscreen.i)
  ForEach Controls()
    If Controls()\kind = #CTL_SHORTCUT And Controls()\vk = vk
      If Controls()\col = #ACT_LEAVEFULL And fullscreen = 0 : Continue : EndIf
      ProcedureReturn Controls()\col
    EndIf
  Next
  ProcedureReturn 0
EndProcedure

DataSection
  CtlLetters:   ; A..Z: the key and its matrix column, row
  Data.s "A" : Data.i 1, 2 : Data.s "B" : Data.i 3, 4 : Data.s "C" : Data.i 2, 4 : Data.s "D" : Data.i 2, 2
  Data.s "E" : Data.i 1, 6 : Data.s "F" : Data.i 2, 5 : Data.s "G" : Data.i 3, 2 : Data.s "H" : Data.i 3, 5
  Data.s "I" : Data.i 4, 1 : Data.s "J" : Data.i 4, 2 : Data.s "K" : Data.i 4, 5 : Data.s "L" : Data.i 5, 2
  Data.s "M" : Data.i 4, 4 : Data.s "N" : Data.i 4, 7 : Data.s "O" : Data.i 4, 6 : Data.s "P" : Data.i 5, 1
  Data.s "Q" : Data.i 7, 6 : Data.s "R" : Data.i 2, 1 : Data.s "S" : Data.i 1, 5 : Data.s "T" : Data.i 2, 6
  Data.s "U" : Data.i 3, 6 : Data.s "V" : Data.i 3, 7 : Data.s "W" : Data.i 1, 1 : Data.s "X" : Data.i 2, 7
  Data.s "Y" : Data.i 3, 1 : Data.s "Z" : Data.i 1, 4
  CtlDigits:    ; 0..9
  Data.i 4, 3, 7, 0, 7, 3, 1, 0, 1, 3, 2, 0, 2, 3, 3, 0, 3, 3, 4, 0
EndDataSection
