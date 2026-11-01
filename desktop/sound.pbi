; Sound on the PC: the SID's 48 kHz mono samples (its ring, SidPcm) to the sound card, through the
; engine's GL_AudioOpen / Next / Play / Queued (Windows waveOut, Linux ALSA): four 1024-sample buffers
; (about 85 ms queued at most), each sample sent to both channels.
EnableExplicit

#SOUND_BUFFERS = 4
#SOUND_SAMPLES = 1024

Global SoundOn.i, SoundMuted.i, SoundUnderruns.i, SoundQueued.i, SoundCursor.i
Global *SoundSlot                ; a buffer the card gave that waits for samples (0: none held)

; The SID samples not yet sent (the cursor jumps forward if it fell a whole ring behind).
Procedure.i SoundAvailable()
  If SidSamples - SoundCursor > #SID_RING - #SOUND_SAMPLES : SoundCursor = SidSamples - #SOUND_SAMPLES : EndIf
  ProcedureReturn SidSamples - SoundCursor
EndProcedure
Procedure SoundReset()
  SoundCursor = SidSamples
EndProcedure

Procedure.i SoundBegin()
  If GL_AudioOpen(48000, #SOUND_SAMPLES, #SOUND_BUFFERS) = #False : ProcedureReturn 0 : EndIf
  SoundOn = 1 : SoundReset()
  ProcedureReturn 1
EndProcedure

; Fill every buffer the card has free. Returns the samples the card still has queued.
Procedure.i SoundPump()
  Protected k.i, v.i, *dst
  If SoundOn = 0 : SoundReset() : ProcedureReturn 0 : EndIf
  Repeat
    If *SoundSlot = 0 : *SoundSlot = GL_AudioNext() : EndIf
    If *SoundSlot = 0 Or SoundAvailable() < #SOUND_SAMPLES : Break : EndIf
    *dst = *SoundSlot
    For k = 0 To #SOUND_SAMPLES - 1
      v = SidPcm((SoundCursor + k) & (#SID_RING - 1))
      If SoundMuted : v = 0 : EndIf
      PokeW(*dst + k * 4, v) : PokeW(*dst + k * 4 + 2, v)
    Next
    SoundCursor + #SOUND_SAMPLES
    GL_AudioPlay(*SoundSlot) : *SoundSlot = 0
  ForEver
  SoundQueued = GL_AudioQueued()
  If SoundQueued = 0 : SoundUnderruns + 1 : EndIf
  ProcedureReturn SoundQueued
EndProcedure

Procedure SoundEnd()
  GL_AudioClose()
  *SoundSlot = 0 : SoundOn = 0
EndProcedure
