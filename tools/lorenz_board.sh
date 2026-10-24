#!/bin/bash
# The three Lorenz CPU batches on the Pico W, one lease each, logs in docs/.
cd "$(dirname "$0")/.."
for i in 1 2 3; do
  secs=420; [ $i = 2 ] && secs=360; [ $i = 3 ] && secs=90
  tools/board.sh src/tests/lorenz$i.picow src/tests/lorenz$i.uf2 $secs > docs/lorenz-picow-batch$i.log 2>&1
  grep -a "LORENZ_RESULT\|LORENZ_NEXT\|FAILED\|STOPPED" docs/lorenz-picow-batch$i.log
  sleep 120
done
