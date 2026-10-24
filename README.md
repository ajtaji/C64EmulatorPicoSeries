# PureMetal C64 for the Raspberry Pi Pico series, and for the desktop

A Commodore 64 emulator written twice from one source:

- **on the Raspberry Pi Pico W** (and Pico 2 W) in PureMetal, compiled with PureMetal Forge to bare-metal
  code: the picture on the LAFVIN ST7796 panel, the SID on a Bluetooth speaker, the LAFVIN stick and
  buttons as the joystick;
- **on the PC** as a PureBasic program drawn with the Neon Arcade Display Engine, with the SID through the
  sound card, the PC keyboard as the C64's, and debug panes.

**No ROMs are included.** The C64's BASIC, KERNAL and character ROMs (and any games) are copyrighted: bring
your own. Without them both versions run a built-in demo of this project's own.

## What is emulated

| Part | What it does |
|---|---|
| 6510 | every NMOS opcode, the undocumented ones included, cycle-counted (page crossings, taken branches), the double write of read-modify-write instructions, the I/O port at $00/$01 (bits 3, 6 and 7 hold their level as inputs) |
| PLA | LORAM / HIRAM / CHAREN and the cartridge's EXROM / GAME: all memory configurations, Ultimax included; RAM under every ROM |
| VIC-II | PAL (312 lines, 63 cycles) and NTSC (263, 65); line by line, with the chip's own badline / display / idle logic (VC, VCBASE, RC); text, multicolour text, extended-colour, bitmap and multicolour bitmap modes; X/Y scroll; 38/40 columns, 24/25 rows; the vertical border flip-flop (open borders work); 8 sprites with X/Y expansion, multicolour, priority, both collisions; raster IRQ; badlines and sprite DMA take their cycles from the CPU |
| CIA x2 | both timers (one-shot, continuous, timer B counting timer A), exact to the cycle at every register access; TOD with alarm; ICR / masks; IRQ (CIA 1) and NMI (CIA 2); keyboard matrix scanned both ways; joysticks in both ports; CIA 2's VIC bank |
| SID | 3 voices: triangle, saw, pulse, noise and their combinations, hard sync, ring modulation, the real envelope rate table with its exponential decay, a state-variable filter (low / band / high pass, cutoff, resonance), volume with its DC offset (so $D418 digis play); 48 kHz |
| Loading | a .PRG put straight into RAM (BASIC pointers set, RUN typed); a .D64 in drive 8 through a trap on the KERNAL's LOAD: wildcards, `LOAD"$",8` directories, `,8,1` |

## A demo written in PureMetal

`demo/` holds a C64 program written in PureMetal itself and compiled by PureMetal Forge for its
Commodore 64 board: raster bars, a smooth scroller, a bouncing sprite and three SID voices
(`demo/README.md`). It runs on a real C64 as well as in this emulator.

Not yet: a real 1541 (fast loaders that drive the disk themselves), cartridges from .CRT files, tape.
A KERNAL without Commodore's LOAD code at $F4A5 (the free MEGA65 Open ROMs used for testing) gets the disk
trap at its $FFD5 jump-table entry instead.

## Tests

Wolfgang Lorenz's C64 test suite 2.15 (public domain, `tests/lorenz/`):

- every 6510 test (238, from `start` to `trap17`) passes on the desktop core, on the whole desktop
  machine, and on the Pico W in three flash-embedded batches (`src/tests/lorenzN.picow`;
  `docs/lorenz-picow-batch*.log`), executing the same instruction counts as the desktop;
- `cputiming` (instruction timing measured with a CIA timer) and `cpuport` pass on the whole machine;
- the CIA, IRQ and banking tests that follow need the real KERNAL's state and are run once ROMs are present.

## Pico W

Wiring is the LAFVIN kit's: LCD SCK GP2, MOSI GP3, CS GP5, DC GP6, RST GP7 (SPI0, 100 MHz); stick on
GP26/GP27; button A GP15 (fire), button B GP14 (SPACE).

Core 0 runs the machine a frame at a time, paced to 50.12 Hz (PAL); core 1 converts each line to RGB565
and streams it to the panel by DMA, and drives the radio. The 384 x 272 picture sits 1:1 in the middle
of the 480 x 320 panel.

Measured on the Pico W (COM7, 200 MHz, the time split from the firmware's status line):

| Program | Frames/s | Worst frame | CPU | VIC-II | SID + line end |
|---|---:|---:|---:|---:|---:|
| BASIC at READY. (Open ROMs) | 50.1 (real time) | 17.9 ms | 4.1 ms | 11.3 ms | 1.7 ms |
| Built-in demo: 3-voice music, sprite, raster IRQs | 50.1 (real time) | 19.0-19.7 ms | 4.6 ms | 8.3 ms | 5.6 ms |
| Dungeon of ROTT V2 (free SEUCK game) from a .D64, in play | 50.1 (real time) | 18.9 ms | 5.5 ms | 9.3 ms | 2.8 ms |
| `demo/c64demo.prg` (PureMetal: raster bars, scroller, sprite, 3 voices) | 50.1 (real time) | 18.7 ms | 4.5 ms | 7.8 ms | 5.1 ms |

No late frame in any of these runs (`docs/board-rott-pmdemo-4.log`). The VIC-II time includes any
wait for core 1 to take lines from the ring: at BASIC, with little else to do, that is 5 ms a frame.

With the Bluetooth speaker playing (A2DP, SBC stereo 48 kHz, encoded on core 1) the demo holds
51 frames/s, worst frame 19.6 ms, no buffer underrun (`docs/board-audio-picow.log`). A PAL frame is 19.95 ms. The 6510 runs 1.6 M instructions/s (a C64 needs about 0.3 M). On the Pico W
the SID is synthesised at 24 kHz and each sample written twice into the 48 kHz stream.

ROMs and programs go in the C64's flash region ($1F0000, 60 KB):

```
py -3 tools/c64_store.py --roms <your ROM folder> --prg game.prg --d64 disk.d64 -o build/c64-store.bin
powershell -File tools/store_write.ps1 -Store build/c64-store.bin
```

A .D64 is stored sparse (only the sectors in use), so a disk with one or two games fits.

Build and run: `powershell -File tools/board.ps1 -Source src/c64.picow -Output build/c64.uf2 -Seconds 60`
(the shared board on this PC is taken through `C:\PMFBuild\board-leases\lease.ps1`). Sound needs a
private wrapper with the speaker's address (see `src/pico_audio.pmi`); the public build is silent.

USB serial: anything typed goes to the C64's keyboard; `` `s `` prints the screen, `` `l `` types
`LOAD"*",8,1` and RUN, `` `0 ``-`` `9 `` run the store's .PRGs, `` `b `` boots BASIC, `` `d `` the demo,
`` `r `` resets. A status line comes once a second.

## Desktop

```
& "C:\Program Files\PureBasic\Compilers\pbcompilerc.exe" desktop\c64_desktop.pb /EXE desktop\PureMetalC64.exe /THREAD /DPIAWARE /OPTIMIZER
desktop\PureMetalC64.exe [program.prg|disk.d64] [--roms folder]
```

Choose the ROM folder once with the toolbar's **ROMs...** (it is remembered). Keys: the PC keyboard is the
C64's (Esc = RUN/STOP, Tab = CTRL, Left Ctrl = C=, Page Up = RESTORE, Home = CLR/HOME, F1-F4, keypad 5 / 7
= F5 / F7); arrows + Right Ctrl are the joystick in port 2 (the toolbar switches ports or turns it off).
F5 run/pause, F6 step, F7 frame, F8 reset, F11 full screen. Panes: CPU (registers, disassembly, memory),
VIC-II, SID (voices and the output), CIAs (timers, TOD, keyboard matrix), Tests (Lorenz's CPU tests on the
running machine), Programs.

`desktop\c64_check.exe` is the console check: `--bench [test]` (Lorenz on the whole machine),
`--demo`, `--boot <romdir> [--prg f] [--d64 f] [--type text] [--frames n] [--shot f.bmp] [--wav f.wav]`.

## Layout

| Path | What |
|---|---|
| `tools/gen_cpu.py` | the 6510, generated for both languages from one opcode table |
| `src/*.pmi` | the machine (shared by both chips and, through `tools/port_desktop.py`, by the desktop) |
| `src/pico_*.pmi`, `src/platform_*`, `src/libs_*` | the Pico side: panel, audio, controls, flash store |
| `src/c64.picow`, `src/c64.pico2w` | the firmware wrappers |
| `desktop/` | the PC program and its console check |
| `tests/lorenz/`, `tests/demo.prg` | the test suite, and the built-in demo (`tools/make_demo.py`) |
