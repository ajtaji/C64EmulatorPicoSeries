"""Drive a running C64 firmware over USB serial from a small script, logging everything it prints.

  py -3 tools/serial_script.py --port COM7 --script tests/boot.txt --log docs/x.log [--open-timeout 20]

Script lines:
  wait <seconds>          read for that long
  send <text>             send text (\\n = RETURN, \\` = a backtick command prefix)
  expect <text> <secs>    read until the text appears (fails the run if it does not)
  # ...                   comment
Exit 0 when every expect was met.
"""
import argparse, sys, time
import serial

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--port', default='COM7')
    ap.add_argument('--script', required=True)
    ap.add_argument('--log', required=True)
    ap.add_argument('--open-timeout', type=float, default=20)
    a = ap.parse_args()
    t0 = time.time(); ser = None
    while ser is None:
        try:
            ser = serial.Serial(a.port, 115200, timeout=0.1)
        except Exception:
            if time.time() - t0 > a.open_timeout:
                print(f'cannot open {a.port}'); return 2
            time.sleep(0.5)
    buf = bytearray(); ok = True
    log = open(a.log, 'w', encoding='utf-8', errors='replace')
    def pump(sec, until=None):
        end = time.time() + sec
        while time.time() < end:
            d = ser.read(4096)
            if d:
                buf.extend(d); log.write(d.decode('latin-1')); log.flush()
                if until and until.encode() in buf: return True
        return until is None
    for line in open(a.script, encoding='utf-8'):
        line = line.rstrip('\n')
        if not line.strip() or line.startswith('#'): continue
        cmd, _, rest = line.partition(' ')
        if cmd == 'wait':
            pump(float(rest))
        elif cmd == 'send':
            text = rest.replace('\\n', '\r').replace('\\`', '`')
            for ch in text:
                ser.write(ch.encode('latin-1')); time.sleep(0.02)
            log.write(f'\n>>> sent {rest}\n')
        elif cmd == 'expect':
            what, _, secs = rest.rpartition(' ')
            del buf[:]
            got = pump(float(secs), what)
            log.write(f'\n>>> expect {what!r}: {"ok" if got else "NOT SEEN"}\n')
            print(f'expect {what!r}: {"ok" if got else "NOT SEEN"}')
            ok = ok and got
    log.close(); ser.close()
    return 0 if ok else 1

if __name__ == '__main__':
    sys.exit(main())
