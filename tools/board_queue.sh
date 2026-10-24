#!/bin/bash
# Board runs in order, one lease each, 2 minutes apart after long runs.
#   tools/board_queue.sh <source> <seconds> [<source> <seconds> ...]
cd "$(dirname "$0")/.."
while [ $# -ge 2 ]; do
  src=$1; secs=$2; shift 2
  name=$(basename "$src"); name=${name%.*}-$(echo "$src" | sed 's/.*\.//')
  powershell -NoProfile -ExecutionPolicy Bypass -File tools/board.ps1 -Source "$src" -Output "build/$name.uf2" -Seconds $secs > "docs/board-$name.log" 2>&1
  echo "== $src rc=$?"; grep -a "LORENZ_RESULT\|LORENZ_NEXT\|FAILED\|STOPPED\|lease\|released\|WARN\|C64_STATUS\|C64 " "docs/board-$name.log" | head -20
  [ $# -ge 2 ] && [ $secs -gt 240 ] && sleep 120
done
