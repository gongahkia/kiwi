"""Record exact PTY input without a shell, echo, or line discipline."""
import os
import sys
import tty

tty.setraw(0)
with open(sys.argv[1], "wb", buffering=0) as capture:
    os.write(1, b"IME fixture\x1b]2;ime-fixture-ready\x07")
    while True:
        data = os.read(0, 4096)
        if not data:
            break
        capture.write(data)
