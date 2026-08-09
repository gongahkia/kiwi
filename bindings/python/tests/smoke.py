import os
import sys


if os.name == "nt":
    os.add_dll_directory(os.environ["STROK_LIBRARY_DIR"])

import strok


if strok.abi_version() != 0x00010003:
    raise SystemExit(f"unexpected strok C ABI version: {strok.abi_version():#x}")

if strok.__all__ != ["abi_version"]:
    raise SystemExit("foundation binding exposes APIs beyond ABI smoke coverage")

sys.exit(0)
