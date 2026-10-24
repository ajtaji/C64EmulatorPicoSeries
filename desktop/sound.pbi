; Sound on the PC: the SID's 48 kHz mono samples (its ring, SidPcm) to the sound card.
; Windows: waveOut with four 1024-sample buffers (about 85 ms queued at most). Elsewhere: silent.
EnableExplicit

#SOUND_BUFFERS = 4
#SOUND_SAMPLES = 1024

CompilerIf #PB_Compiler_OS = #PB_OS_Windows
  Structure SoundWaveFormat
    wFormatTag.w : nChannels.w : nSamplesPerSec.l : nAvgBytesPerSec.l : nBlockAlign.w : wBitsPerSample.w : cbSize.w
  EndStructure
  Structure SoundWaveHeader
    *lpData : dwBufferLength.l : dwBytesRecorded.l : *dwUser : dwFlags.l : dwLoops.l : *lpNext : *reserved
  EndStructure
  Import "winmm.lib"
    waveOutOpen_(*handle, device.l, *format, callback.i, instance.i, flags.l) As "waveOutOpen"
    waveOutPrepareHeader_(handle.i, *header, size.l) As "waveOutPrepareHeader"
    waveOutUnprepareHeader_(handle.i, *header, size.l) As "waveOutUnprepareHeader"
    waveOutWrite_(handle.i, *header, size.l) As "waveOutWrite"
    waveOutReset_(handle.i) As "waveOutReset"
    waveOutClose_(handle.i) As "waveOutClose"
  EndImport
  #SOUND_WHDR_DONE = 1
  Global SoundHandle.i
  Global Dim SoundHeaders.SoundWaveHeader(#SOUND_BUFFERS)
  Global Dim SoundData.w(#SOUND_BUFFERS * #SOUND_SAMPLES)
CompilerEndIf
Global SoundOn.i, SoundMuted.i, SoundUnderruns.i, SoundQueued.i, SoundCursor.i

; The SID samples not yet sent (the cursor jumps forward if it fell a whole ring behind).
Procedure.i SoundAvailable()
  If SidSamples - SoundCursor > #SID_RING - #SOUND_SAMPLES : SoundCursor = SidSamples - #SOUND_SAMPLES : EndIf
  ProcedureReturn SidSamples - SoundCursor
EndProcedure
Procedure SoundReset()
  SoundCursor = SidSamples
EndProcedure

Procedure.i SoundBegin()
  CompilerIf #PB_Compiler_OS = #PB_OS_Windows
    Protected fmt.SoundWaveFormat, i.i
    fmt\wFormatTag = 1 : fmt\nChannels = 1 : fmt\nSamplesPerSec = 48000 : fmt\wBitsPerSample = 16
    fmt\nBlockAlign = 2 : fmt\nAvgBytesPerSec = 96000
    If waveOutOpen_(@SoundHandle, -1, @fmt, 0, 0, 0) <> 0 : SoundHandle = 0 : ProcedureReturn 0 : EndIf
    For i = 0 To #SOUND_BUFFERS - 1
      SoundHeaders(i)\lpData = @SoundData(i * #SOUND_SAMPLES)
      SoundHeaders(i)\dwBufferLength = #SOUND_SAMPLES * 2
      SoundHeaders(i)\dwFlags = #SOUND_WHDR_DONE
    Next
    SoundOn = 1 : SoundReset()
    ProcedureReturn 1
  CompilerElse
    ProcedureReturn 0
  CompilerEndIf
EndProcedure

; Fill every finished buffer. Returns the samples the card still has queued.
Procedure.i SoundPump()
  CompilerIf #PB_Compiler_OS = #PB_OS_Windows
    Protected i.i, k.i, *dst, queued.i
    If SoundOn = 0 : SoundReset() : ProcedureReturn 0 : EndIf
    For i = 0 To #SOUND_BUFFERS - 1
      If SoundHeaders(i)\dwFlags & #SOUND_WHDR_DONE
        If SoundHeaders(i)\dwFlags & 2 : waveOutUnprepareHeader_(SoundHandle, @SoundHeaders(i), SizeOf(SoundWaveHeader)) : EndIf
        If SoundAvailable() < #SOUND_SAMPLES : Continue : EndIf
        *dst = @SoundData(i * #SOUND_SAMPLES)
        For k = 0 To #SOUND_SAMPLES - 1
          PokeW(*dst + k * 2, SidPcm((SoundCursor + k) & (#SID_RING - 1)))
        Next
        SoundCursor + #SOUND_SAMPLES
        If SoundMuted : FillMemory(*dst, #SOUND_SAMPLES * 2, 0) : EndIf
        SoundHeaders(i)\dwFlags = 0
        waveOutPrepareHeader_(SoundHandle, @SoundHeaders(i), SizeOf(SoundWaveHeader))
        waveOutWrite_(SoundHandle, @SoundHeaders(i), SizeOf(SoundWaveHeader))
      EndIf
    Next
    For i = 0 To #SOUND_BUFFERS - 1
      If (SoundHeaders(i)\dwFlags & #SOUND_WHDR_DONE) = 0 : queued + #SOUND_SAMPLES : EndIf
    Next
    If queued = 0 : SoundUnderruns + 1 : EndIf
    SoundQueued = queued
    ProcedureReturn queued
  CompilerElse
    SoundReset()
    ProcedureReturn 0
  CompilerEndIf
EndProcedure

Procedure SoundEnd()
  CompilerIf #PB_Compiler_OS = #PB_OS_Windows
    Protected i.i
    If SoundHandle
      waveOutReset_(SoundHandle)
      For i = 0 To #SOUND_BUFFERS - 1 : waveOutUnprepareHeader_(SoundHandle, @SoundHeaders(i), SizeOf(SoundWaveHeader)) : Next
      waveOutClose_(SoundHandle) : SoundHandle = 0
    EndIf
  CompilerEndIf
  SoundOn = 0
EndProcedure
