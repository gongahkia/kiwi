"""Headless command-line entry points."""

from __future__ import annotations

import argparse
import sys
from collections.abc import Sequence

_MINIMUM_PYTHON = (3, 12)


def doctor() -> int:
    """Check the minimum headless runtime contract."""
    if sys.version_info[:2] < _MINIMUM_PYTHON:
        print("kiwi doctor: Python 3.12 or later is required", file=sys.stderr)
        return 1
    if "pygame" in sys.modules:
        print("kiwi doctor: pygame was imported", file=sys.stderr)
        return 1
    print("kiwi doctor: ok")
    print(f"python: {sys.version_info.major}.{sys.version_info.minor}")
    print("pygame imported: no")
    return 0


def main(argv: Sequence[str] | None = None) -> int:
    """Run the Kiwi command-line interface."""
    parser = argparse.ArgumentParser(prog="kiwi")
    parser.add_argument("command", choices=("doctor",))
    parser.parse_args(argv)
    return doctor()


if __name__ == "__main__":
    raise SystemExit(main())
