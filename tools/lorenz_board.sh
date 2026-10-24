#!/bin/bash
# The three Lorenz CPU batches on the Pico W, one lease each (tools/board.ps1), logs in docs/.
cd "$(dirname "$0")/.."
for i in 1 2 3; do
  secs=420; [ $i = 2 ] && secs=360; [ $i = 3 ] && secs=90
  powershell -NoProfile -ExecutionPolicy Bypass -File tools/board.ps1 -Source src/tests/lorenz$i.picow -Output build/lorenz$i.uf2 -Seconds $secs > docs/lorenz-picow-batch$i.log 2>&1
  grep -a "LORENZ_RESULT\|LORENZ_NEXT\|FAILED\|STOPPED\|lease\|released\|WARN" docs/lorenz-picow-batch$i.log
  [ $i = 3 ] || sleep 120
done
