"""Raw PTY receiver for isolated X11 primary-selection qualification."""
import os
import sys
import termios
import tty

original = termios.tcgetattr(0)
try:
    tty.setraw(0)
    with open(sys.argv[1], "wb", buffering=0) as capture:
        os.write(1, "primary 中\r\n\x1b[?2004h\x1b]2;primary-fixture-ready\x07".encode())
        while True:
            value = os.read(0, 4096)
            if not value:
                break
            capture.write(value)
finally:
    termios.tcsetattr(0, termios.TCSANOW, original)
