# PureMetal C64 demo

`c64demo.c64` is a C64 program written in PureMetal and compiled by PureMetal Forge for its
"Commodore 64 (PAL)" board (extension `.c64`): raster bars (16 raster interrupts a frame), a smooth
scroller on the bottom row, a bouncing ball sprite, and three SID voices (pulse bass, triangle lead,
a sawtooth arpeggio) playing Am F C G.

The tables in it (screen codes, SID frequencies, the song, the sprite) are written by
`tools/make_pm_demo.py` from `tools/pm_demo_body.c64`, so edit the body there and run:

```
py -3 tools/make_pm_demo.py
PureMetalForge.exe --compile demo\c64demo.c64 -o demo\c64demo.hex
```

The compiler writes `c64demo.prg` beside the `.hex` (`10 SYS 2061`, code at $080D). On any C64,
or this emulator: `LOAD"C64DEMO",8,1` and `RUN`, or `desktop\c64_check.exe --boot <roms> --prg demo\c64demo.prg`.
Built with the compiler at main 9b5dfd993 (3,430 bytes).
