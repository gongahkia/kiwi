"""Bounded PTY peer for the external Cocoa accessibility smoke test."""
import os
from pathlib import Path
import sys
import termios
import time
import tty

control = Path(sys.argv[1])
(control.parent / "child.pid").write_text(str(os.getpid()))
previous = termios.tcgetattr(0)
last = ""
try:
    tty.setraw(0)
    os.write(1, "\x1b[2J\x1b[Halpha 界 😀\r\nbeta é\r\nlast ✓\x1b]2;kiwi-ax-ready\x07".encode())
    deadline = time.monotonic() + 45
    while time.monotonic() < deadline:
        request = control.read_text() if control.exists() else ""
        if request == "stop":
            break
        if request and request != last:
            if request == "unchanged":
                for _ in range(10):
                    os.write(1, b"\x1b[0m")
                    time.sleep(.02)
                os.write(1, b"\x1b]2;kiwi-ax-unchanged\x07")
            elif request == "update":
                os.write(1, "\r\nupdated ✓\x1b]2;kiwi-ax-updated\x07".encode())
            else:
                raise AssertionError("unknown fixture request")
            last = request
        time.sleep(.02)
finally:
    termios.tcsetattr(0, termios.TCSANOW, previous)
