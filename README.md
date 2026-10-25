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

`tests/selftest.prg` (from `tools/make_selftest.py`) is the machine checking itself with no KERNAL code:
PLA banking, keyboard matrix, CIA 1 timer A (and its timing), TOD, raster IRQ, sprite collisions,
badline cycle stealing, SID OSC3 / ENV3 and a CIA 2 timer NMI, one line each on the screen. All pass on
the desktop (bare: `c64_check --demo --prg tests\selftest.prg`; and RUN from BASIC) and on the Pico W
(`tests/board/selftest.txt`, `docs/board-selftest.log`).

## Pico W and Pico 2 W

Wiring is the LAFVIN kit's on both: LCD SCK GP2, MOSI GP3, CS GP5, DC GP6, RST GP7 (SPI0); stick on
GP26/GP27; button A GP15 (fire), button B GP14 (SPACE).

**NTSC by default.** The C64 was a US machine: the Pico starts as the NTSC C64 (6567: 263 lines of 65
cycles, 1.0227 MHz, 59.83 frames/s, a 384 x 242 view); `` `v `` over USB switches to PAL (6569: 312 x 63,
0.985 MHz, 50.12 frames/s, 384 x 272) and back. The picture sits 1:1 in the middle of the 480 x 320 panel.

**Both cores work.** Core 0 runs the 6510, both CIAs, the SID and the VIC-II's line logic (raster,
badlines, VC / RC, the border flip-flops, sprite DMA) and leaves each visible line as a record; core 1
draws the records (cells, sprites, borders, the collisions), converts them to RGB565 (in the chip's own
assembly) and sends them to the panel by DMA, and drives the radio. The panel skips a frame when its
link is behind - the machine does not: every frame is still drawn, so sprite collisions stay exact.

On the RP2350 the 6510 is `src/cpu6510_m33.pico2` (from `tools/gen_cpu_m33.py`): the same handlers with
each instruction's tail (count, budget, opcode fetch through the page table, `ldr pc` through the
dispatch table) and its operand fetches in Thumb-2. The RP2040 keeps the Thumb-1 `cpu6510.pmi`.

Measured (compiler 883c4ae12; frames/s machine / panel; busy = each core's working time a second):

| Board | Standard | Program | Frames/s | Worst frame | Core 0 busy | Core 1 busy |
|---|---|---|---:|---:|---:|---:|
| Pico W (RP2040, 200 MHz, SPI 100 MHz) | NTSC | BASIC, self-test, PureMetal demo | 60 / 60 | 12.4 ms | 57-60% | 61-63% |
| | NTSC | Dungeon of ROTT, in play | 60 / 57-58 | 14.8 ms | 69-82% | 61-63% |
| | PAL | all four | 51 / 51 | 16.0 ms | 56-80% | 58-60% |
| Pico 2 W (RP2350, 150 MHz, SPI 75 MHz) | NTSC | all four | 60 / 44-45 | 13.8 ms | 57-82% | 48-54% |
| | PAL | all four | 51 / 38 | 18.9 ms | 56-96%* | 46-49% |

No late frame in any run (`docs/board-picow-ntsc.log`, `board-picow-pal.log`, `board-pico2w-ntsc.log`,
`board-pico2w-pal-sid48k.log`). On the Pico 2 W the panel's link is the limit: the RP2350 stays at its
SDK-proven 150 MHz, so SPI0 runs at 75 MHz and a 384-pixel line takes 82 us - at most ~50 frames/s NTSC,
~45 PAL. *That PAL run still synthesised the SID at 48 kHz; it now runs at 24 kHz on every Pico (each
sample written twice into the 48 kHz stream), which took the 3-voice demo's core 0 from 97% to 82% at NTSC.

The 6510, Lorenz's CPU tests (batch 1: 140 tests, 608 M instructions), all passing:

| Board | Core | Instructions/s |
|---|---|---:|
| Pico W | Thumb-1 (`cpu6510.pmi`) | 1.60 M |
| Pico 2 W | the same core | 1.49 M |
| Pico 2 W | Thumb-2 (`cpu6510_m33.pico2`) | 1.88 M (+26%) |

A C64 needs about 0.3 M a second. With the Bluetooth speaker playing (Pico W, A2DP, SBC stereo 48 kHz,
encoded on core 1) the PAL demo held 51 frames/s with no buffer underrun (`docs/board-audio-picow.log`,
before the two-core split; the speaker is not tested on the new build yet).

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
desktop\PureMetalC64.exe [program.prg|disk.d64] [--roms folder] [--pal] [--mute]
```

The window starts as the NTSC C64 (60 frames/s); the toolbar's NTSC / PAL button or `--pal` switches.

Choose the ROM folder once with the toolbar's **ROMs...** (it is remembered). Keys: the PC keyboard is the
C64's (Esc = RUN/STOP, Tab = CTRL, Left Ctrl = C=, Page Up = RESTORE, Home = CLR/HOME, F1-F4, keypad 5 / 7
= F5 / F7); arrows + Right Ctrl are the joystick in port 2 (the toolbar switches ports or turns it off).
F5 run/pause, F6 step, F7 frame, F8 reset, F11 full screen. Panes: CPU (registers, disassembly, memory),
VIC-II, SID (voices and the output), CIAs (timers, TOD, keyboard matrix), Tests (Lorenz's CPU tests on the
running machine), Programs.

`desktop\c64_check.exe` is the console check (PAL unless `--ntsc`: its reference pictures are PAL):
`--bench [test]` (Lorenz on the whole machine), `--demo [--prg f]`, `--boot <romdir> [--prg f] [--d64 f] [--type text] [--frames n] [--shot f.bmp] [--wav f.wav]`.

## Layout

| Path | What |
|---|---|
| `tools/gen_cpu.py` | the 6510, generated for both languages from one opcode table |
| `tools/gen_cpu_m33.py` | the RP2350's 6510 (`src/cpu6510_m33.pico2`): the same handlers, Thumb-2 tails and fetches |
| `src/*.pmi` | the machine (shared by both chips and, through `tools/port_desktop.py`, by the desktop) |
| `src/pico_*.pmi`, `src/platform_*`, `src/libs_*` | the Pico side: panel, audio, controls, flash store |
| `src/c64.picow`, `src/c64.pico2w` | the firmware wrappers |
| `desktop/` | the PC program and its console check |
| `tests/lorenz/`, `tests/demo.prg` | the test suite, and the built-in demo (`tools/make_demo.py`) |
