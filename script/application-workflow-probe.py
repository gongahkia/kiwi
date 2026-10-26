"""Bounded real-PTY query/keyboard handshake used by test-applications."""
import json
import os
from pathlib import Path
import re
import select
import sys
import termios
import time
import tty

mode, label = sys.argv[1:]
assert mode in ("legacy", "kitty") and re.fullmatch(r"[a-z-]+", label)
original = termios.tcgetattr(0)
observed = {}


def response(pattern):
    data = b""
    deadline = time.monotonic() + 5
    while time.monotonic() < deadline:
        if select.select([0], [], [], max(0, deadline - time.monotonic()))[0]:
            chunk = os.read(0, 256)
            assert chunk, "PTY closed during query"
            data += chunk
            assert len(data) <= 256, "query response exceeded bound"
            if re.fullmatch(pattern, data):
                return data.decode("ascii")
    raise AssertionError(f"missing or unexpected response: {data!r}")


try:
    tty.setraw(0)
    os.write(1, b"\x1b[2J\x1b[2;3H\x1b[6n")
    observed["cursor"] = response(rb"\x1b\[2;3R")
    os.write(1, b"\x1b[c")
    observed["attributes"] = response(rb"\x1b\[\?[0-9;]+c")
    if mode == "kitty":
        # Headless model supports flags 1,2,8,16. Alternate physical key data
        # requires native input and is qualified by separate desktop tests.
        os.write(1, b"\x1b[>27u\x1b[?u")
        observed["keyboard"] = response(rb"\x1b\[\?27u")
    os.write(1, ("\r\nKIWI-PROBE-READY-" + label + "\r\n").encode())
    observed["input"] = response(rb"\x1b\[0;;120u" if mode == "kitty" else rb"x")
finally:
    if mode == "kitty":
        os.write(1, b"\x1b[<u")
    termios.tcsetattr(0, termios.TCSANOW, original)
Path("probe-" + label + ".json").write_text(json.dumps(observed) + "\n")
print("KIWI-PROBE-DONE-" + label, flush=True)
