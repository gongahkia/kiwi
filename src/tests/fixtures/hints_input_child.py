"""Raw receiver used to prove URL hint commands never reach terminal input."""
import os
import signal
import sys
import termios
import tty

original = termios.tcgetattr(0)


def repaint(*_):
    os.write(1, b"\x1b[2J\x1b[H(https://a.example/path(test)).\r\n")
    os.write(1, b"\x1b]8;;https://actual.example/target\x1b\\https://display.example\x1b]8;;\x1b\\\r\n")
    os.write(1, ("https://long.example/" + "a" * (os.get_terminal_size().columns + 20) + "\r\n").encode())
    os.write(1, b"\x1b]2;hints-fixture-ready\x07")


try:
    tty.setraw(0)
    with open(sys.argv[1], "wb", buffering=0) as received:
        signal.signal(signal.SIGWINCH, repaint)
        os.write(1, b"\x1b[>31u\x1b[?2004h")
        repaint()
        while True:
            data = os.read(0, 4096)
            if not data:
                break
            received.write(data)
finally:
    termios.tcsetattr(0, termios.TCSANOW, original)
