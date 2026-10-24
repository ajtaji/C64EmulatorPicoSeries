; The PC keyboard as the C64's 8 x 8 matrix, by position where the keys match and by
; meaning where they do not:
;   letters, digits, Space, Return; Backspace = INST/DEL; Esc = RUN/STOP; Tab = CTRL;
;   Left Ctrl = C=; Shifts = the C64's shifts; Home = CLR/HOME; Page Up = RESTORE;
;   cursor Right / Down = CRSR (Left / Up add SHIFT); F1 F3 F5 F7 (F2 F4 F6 F8 add SHIFT);
;   - = +  [ ] ; ' , . / and \ = the C64's - = @ * : ; , . / and pound; ` = left arrow;
;   Insert = +, Delete = up arrow.
; With joystick keys on, the arrows and Right Ctrl (or Right Alt) are the joystick instead.
EnableExplicit
Global Dim KbMap.i(256)          ; PC key -> C64 key (col * 8 + row), -1 none; +64 = with SHIFT
Global KbJoyKeys.i = 1, KbJoyPort.i = 2
Global KbRestoreHeld.i

Procedure KbSet(pc.i, col.i, row.i, shift.i = 0)
  KbMap(pc) = col * 8 + row + shift * 64
EndProcedure

Procedure KbInit()
  Protected i.i
  For i = 0 To 255 : KbMap(i) = -1 : Next
  ; letters
  KbSet(#PB_Shortcut_A, 1, 2) : KbSet(#PB_Shortcut_B, 3, 4) : KbSet(#PB_Shortcut_C, 2, 4) : KbSet(#PB_Shortcut_D, 2, 2)
  KbSet(#PB_Shortcut_E, 1, 6) : KbSet(#PB_Shortcut_F, 2, 5) : KbSet(#PB_Shortcut_G, 3, 2) : KbSet(#PB_Shortcut_H, 3, 5)
  KbSet(#PB_Shortcut_I, 4, 1) : KbSet(#PB_Shortcut_J, 4, 2) : KbSet(#PB_Shortcut_K, 4, 5) : KbSet(#PB_Shortcut_L, 5, 2)
  KbSet(#PB_Shortcut_M, 4, 4) : KbSet(#PB_Shortcut_N, 4, 7) : KbSet(#PB_Shortcut_O, 4, 6) : KbSet(#PB_Shortcut_P, 5, 1)
  KbSet(#PB_Shortcut_Q, 7, 6) : KbSet(#PB_Shortcut_R, 2, 1) : KbSet(#PB_Shortcut_S, 1, 5) : KbSet(#PB_Shortcut_T, 2, 6)
  KbSet(#PB_Shortcut_U, 3, 6) : KbSet(#PB_Shortcut_V, 3, 7) : KbSet(#PB_Shortcut_W, 1, 1) : KbSet(#PB_Shortcut_X, 2, 7)
  KbSet(#PB_Shortcut_Y, 3, 1) : KbSet(#PB_Shortcut_Z, 1, 4)
  ; digits
  KbSet(#PB_Shortcut_1, 7, 0) : KbSet(#PB_Shortcut_2, 7, 3) : KbSet(#PB_Shortcut_3, 1, 0) : KbSet(#PB_Shortcut_4, 1, 3)
  KbSet(#PB_Shortcut_5, 2, 0) : KbSet(#PB_Shortcut_6, 2, 3) : KbSet(#PB_Shortcut_7, 3, 0) : KbSet(#PB_Shortcut_8, 3, 3)
  KbSet(#PB_Shortcut_9, 4, 0) : KbSet(#PB_Shortcut_0, 4, 3)
  ; the rest
  KbSet(#PB_Shortcut_Space, 7, 4) : KbSet(#PB_Shortcut_Return, 0, 1) : KbSet(#PB_Shortcut_Back, 0, 0)
  KbSet(#PB_Shortcut_Escape, 7, 7) : KbSet(#PB_Shortcut_Tab, 7, 2) : KbSet(#PB_Shortcut_Home, 6, 3)
  KbSet(#PB_Shortcut_Right, 0, 2) : KbSet(#PB_Shortcut_Left, 0, 2, 1)
  KbSet(#PB_Shortcut_Down, 0, 7) : KbSet(#PB_Shortcut_Up, 0, 7, 1)
  KbSet(#PB_Shortcut_F1, 0, 4) : KbSet(#PB_Shortcut_F2, 0, 4, 1) : KbSet(#PB_Shortcut_F3, 0, 5) : KbSet(#PB_Shortcut_F4, 0, 5, 1)
  ; F5..F8 are the window's debug keys; the C64's F5 / F7 are on the numeric keypad's 5 and 7
  KbSet(#PB_Shortcut_Pad5, 0, 6) : KbSet(#PB_Shortcut_Pad7, 0, 3)
  KbSet(#PB_Shortcut_Insert, 5, 0) : KbSet(#PB_Shortcut_Delete, 6, 6)
  KbSet(#VK_OEM_MINUS, 5, 3) : KbSet(#VK_OEM_PLUS, 6, 5) : KbSet(#VK_OEM_4, 5, 6) : KbSet(#VK_OEM_6, 6, 1)
  KbSet(#VK_OEM_1, 5, 5) : KbSet(#VK_OEM_7, 6, 2) : KbSet(#VK_OEM_COMMA, 5, 7) : KbSet(#VK_OEM_PERIOD, 5, 4)
  KbSet(#VK_OEM_2, 6, 7) : KbSet(#VK_OEM_5, 6, 0) : KbSet(#VK_OEM_3, 7, 1)
  KbSet(#VK_LSHIFT, 1, 7) : KbSet(#VK_RSHIFT, 6, 4)
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
  If KbJoyKeys
    If KbDown(#VK_UP) : joy | 1 : EndIf
    If KbDown(#VK_DOWN) : joy | 2 : EndIf
    If KbDown(#VK_LEFT) : joy | 4 : EndIf
    If KbDown(#VK_RIGHT) : joy | 8 : EndIf
    If KbDown(#VK_RCONTROL) Or KbDown(#VK_RMENU) : joy | 16 : EndIf
  EndIf
  For vk = 8 To 254
    k = KbMap(vk)
    If k >= 0 And vk <> #VK_SHIFT And vk <> #VK_CONTROL
      If KbJoyKeys And (vk = #VK_UP Or vk = #VK_DOWN Or vk = #VK_LEFT Or vk = #VK_RIGHT) : Continue : EndIf
      If KbDown(vk)
        col = (k >> 3) & 7 : row = k & 7
        KeyRows(col) | (1 << row)
        If k & 64 : shift = 1 : EndIf
      EndIf
    EndIf
  Next
  If KbDown(#VK_LCONTROL) : KeyRows(7) | (1 << 5) : EndIf
  If shift : KeyRows(1) | (1 << 7) : EndIf
  ; RESTORE is wired to the NMI line, not the matrix
  KbRestoreHeld = KbDown(#VK_PRIOR)
  ProcedureReturn joy
EndProcedure
