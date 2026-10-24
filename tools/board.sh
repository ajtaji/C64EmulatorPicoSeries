#!/bin/bash
# Build, then upload to the shared Pico W (COM7) and capture its serial output,
# holding the bench lease only while the board is in use. The lease is taken and
# released from Bash (the PowerShell tool's sandbox cannot see other leases).
#   tools/board.sh <source> <output.uf2> <seconds> [port]
set -u
cd "$(dirname "$0")/.."
SRC="$1"; OUT="$2"; SECS="${3:-30}"; PORT="${4:-COM7}"
PMF='C:\Users\ajtaj\Desktop\Github\PureBasicCode\OpenGl Work\ArduinoBasic\PureMetalForge.exe'
win() { cygpath -w "$(pwd)/$1"; }
"$PMF" --compile "$(win "$SRC")" -S -o "$(win "$OUT")" > "$OUT.build.log" 2> "$OUT.stderr.log" || { echo "compile failed: $OUT.build.log"; grep -i "error\|PM[0-9]" "$OUT.build.log" | head; exit 1; }
# refuse an image that reaches the NES ROM store at flash $10050000 (or the Ms. Pac-Man pack at $40000)
END=$(py -3 -c "import struct,sys;d=open(sys.argv[1],'rb').read();print(max(struct.unpack_from('<I',d,o+12)[0]+struct.unpack_from('<I',d,o+16)[0] for o in range(0,len(d),512)))" "$OUT")
if [ "$END" -gt $((0x10040000)) ]; then echo "image reaches $END, past \$40000: not uploaded"; exit 1; fi
L=/c/PMFBuild/board-leases/$PORT.lease
release() {
  if [ -e "$L" ] && grep -q "^c64 $$ " "$L" 2>/dev/null; then
    mv -f "$L" "$L.$$.released" 2>/dev/null; rm -f "$L.$$.released"
  fi
  [ -e "$L" ] && grep -q "^c64 $$ " "$L" 2>/dev/null && echo "WARNING: lease $L still present"
}
if [ -z "${LEASE_HELD:-}" ]; then
  mkdir -p /c/PMFBuild/board-leases
  set -o noclobber
  until echo "c64 $$ $(date -Iseconds) upload+capture ${SECS}s, ends by $(date -Iseconds -d "+$((SECS+60)) sec")" 2>/dev/null > "$L"; do sleep 15; done
  set +o noclobber
  trap release EXIT
fi
"$PMF" --compile "$(win "$SRC")" -S -o "$(win "$OUT")" --port "$PORT" --seconds "$SECS" > "$OUT.board.log" 2> "$OUT.stderr.log"
rc=$?
if [ -z "${LEASE_HELD:-}" ]; then release; trap - EXIT; fi
grep -v '^\[DEBUG\]\|^> \|TELEMETRY\|_RP2040\|_RP2350\|^pmfc:' "$OUT.board.log"
exit $rc
