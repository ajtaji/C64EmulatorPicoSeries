# PureMetal C64 demo

`c64demo.c64` is a C64 program written in PureMetal and compiled by PureMetal Forge for its
"Commodore 64 (PAL)" board (extension `.c64`): raster bars (16 raster interrupts a frame), a smooth
scroller on the bottom row, a bouncing ball sprite, and three SID voices (pulse bass, triangle lead,
a sawtooth arpeggio) playing Am F C G.

The scroller's message is a string in the program, turned into screen codes once at the start with
`Len`, `Mid` and `Asc` from the classic-CPU string library. The other tables (the title's screen codes, SID
frequencies, the song, the sprite) are written by
`tools/make_pm_demo.py` from `tools/pm_demo_body.c64`, so edit the body there and run:

```
py -3 tools/make_pm_demo.py
PureMetalForge.exe --compile demo\c64demo.c64 -o demo\c64demo.hex
```

The compiler writes `c64demo.prg` beside the `.hex` (`10 SYS2072`, code at $0818). On any C64,
or this emulator: `LOAD"C64DEMO",8,1` and `RUN`, or `desktop\c64_check.exe --boot <roms> --prg demo\c64demo.prg`.
The demo starts about 4.8 s later than it did with the message as a table, while the message is converted
(before the interrupts start, so the screen is still and silent until then).
Built with the compiler at main b9594c9e3 (6,153 bytes).
