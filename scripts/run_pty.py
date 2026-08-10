#!/usr/bin/env python3
"""Run a command in a fixed-size pseudo-terminal and capture its output."""

import argparse
import fcntl
import os
import select
import signal
import struct
import sys
import termios


def set_window_size(fd: int, rows: int, cols: int) -> None:
    fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack("HHHH", rows, cols, 0, 0))


def drain(master: int, transcript) -> bool:
    saw_eof = False
    while True:
        try:
            chunk = os.read(master, 65536)
        except BlockingIOError:
            return saw_eof
        except OSError:
            return True
        if not chunk:
            saw_eof = True
            return saw_eof
        transcript.write(chunk)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--transcript", required=True)
    parser.add_argument("--rows", type=int, default=24)
    parser.add_argument("--cols", type=int, default=80)
    parser.add_argument("command", nargs=argparse.REMAINDER)
    args = parser.parse_args()
    if args.rows <= 0 or args.cols <= 0:
        parser.error("--rows and --cols must be positive")
    if not args.command or args.command[0] != "--" or len(args.command) == 1:
        parser.error("command must follow --")

    command = args.command[1:]
    master, slave = os.openpty()
    set_window_size(slave, args.rows, args.cols)
    os.set_blocking(master, False)
    child = os.fork()
    if child == 0:
        try:
            os.setsid()
            fcntl.ioctl(slave, termios.TIOCSCTTY, 0)
            os.dup2(slave, 0)
            os.dup2(slave, 1)
            os.dup2(slave, 2)
            os.close(master)
            if slave > 2:
                os.close(slave)
            os.execvpe(command[0], command, os.environ)
        except BaseException as error:
            print(f"pty runner failed to execute {command[0]}: {error}", file=sys.stderr)
            os._exit(127)

    os.close(slave)
    status = None
    try:
        with open(args.transcript, "wb") as transcript:
            while status is None:
                readable, _, _ = select.select([master], [], [], 0.1)
                if readable:
                    drain(master, transcript)
                finished, result = os.waitpid(child, os.WNOHANG)
                if finished == child:
                    status = result
            while not drain(master, transcript):
                readable, _, _ = select.select([master], [], [], 0.1)
                if not readable:
                    break
    except BaseException:
        try:
            os.kill(child, signal.SIGTERM)
        except ProcessLookupError:
            pass
        while True:
            try:
                os.waitpid(child, 0)
                break
            except InterruptedError:
                continue
            except ChildProcessError:
                break
        raise
    finally:
        os.close(master)

    return os.waitstatus_to_exitcode(status)


if __name__ == "__main__":
    raise SystemExit(main())
