"""Real PTY peer for isolated desktop transitions; no terminal-model injection."""
import os
import signal
import termios
import tty

original = termios.tcgetattr(0)
sequence = "ready"


def paint(*_):
    size = os.get_terminal_size(0)
    title = f"kiwi-transition:{sequence}:{size.columns}:{size.lines}"
    os.write(1, ("\x1b]2;" + title + "\x07\x1b[H\x1b[2K" + sequence).encode())


try:
    tty.setraw(0)
    signal.signal(signal.SIGWINCH, paint)
    paint()
    pending = b""
    while True:
        value = os.read(0, 64)
        if not value:
            break
        with open(os.environ["KIWI_TRANSITION_DIRECTORY"] + "/input", "ab") as stream:
            stream.write(value)
        for byte in value:
            if byte in (10, 13):
                sequence = pending.decode("ascii")
                assert sequence.isalpha() and len(sequence) <= 32
                pending = b""
                paint()
            else:
                pending += bytes([byte])
                assert len(pending) <= 32
finally:
    termios.tcsetattr(0, termios.TCSANOW, original)
