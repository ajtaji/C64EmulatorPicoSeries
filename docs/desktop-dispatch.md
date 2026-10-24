# Desktop dispatch: computed goto against a procedure table (2026-10-23)

The same 256 opcode bodies (tools/gen_cpu.py), two ways of reaching them:

- `desktop/core/cpu6510.pbi`: one procedure, labels-as-values through the C back end (`!goto *...`);
- `desktop/core/cpu6510_procs.pbi`: a procedure per opcode, called through a table with `CallFunctionFast`.

Workload: Wolfgang Lorenz's whole 6510 suite (238 tests, 953,591,648 instructions) in
`desktop/lorenz_check.pb` (`/CONSTANT PROCS=1` selects the table), PureBasic 6.41 C back end, x64,
`/OPTIMIZER`, this laptop. Both pass all 238.

| run | goto | procedure table |
|---|---:|---:|
| 1 | 144.2 M instr/s | 137.6 M instr/s |
| 2 | 133.7 | 135.8 |
| 3 | 138.8 | 138.3 |
| best | **144.2** | 138.3 (-4%) |

The computed goto stays. The difference is small because every access goes through the page tables
(the C64's banking), which both variants pay alike. A real C64 needs about 0.3 M instructions/s, so
either is hundreds of times faster than the machine it runs.
