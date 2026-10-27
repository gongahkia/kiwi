"""Controlled raw PTY peer for the external AT-SPI integration test."""
import os
import termios
import tty

previous = termios.tcgetattr(0)
try:
    tty.setraw(0)
    os.write(1, b"\x1b]2;kiwi-atspi-ready\x07")
    while True:
        data = os.read(0, 128)
        if not data or b"q" in data:
            break
        if b"r" in data:
            os.write(1, "\x1b[2J\x1b[Halpha 界\r\nbeta é".encode())
        if b"x" in data:
            os.write(1, "\r\nupdated ✓".encode())
finally:
    termios.tcsetattr(0, termios.TCSANOW, previous)
