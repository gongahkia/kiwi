"""Raw PTY receiver: preserve every input byte so Find isolation is observable."""
import os
import sys
import termios
import tty

original = termios.tcgetattr(0)
try:
    tty.setraw(0)
    with open(sys.argv[1], "wb", buffering=0) as received:
        for index in range(1000):
            os.write(1, f"retained history {index:04d}\r\n".encode())
        os.write(1, "unique é中 needle\r\n\x1b[>31u\x1b[?2004h\x1b]2;search-fixture-ready\x07".encode())
        while True:
            data = os.read(0, 4096)
            if not data:
                break
            received.write(data)
finally:
    termios.tcsetattr(0, termios.TCSANOW, original)
