from __future__ import annotations

import os
from pathlib import Path
from typing import Optional, Tuple

try:
    from setuptools import Extension, setup
    from setuptools.command.build_ext import build_ext
except ImportError:
    from distutils.command.build_ext import build_ext
    from distutils.core import Extension, setup


ROOT = Path(__file__).resolve().parent


def fail(message: str) -> None:
    raise RuntimeError(f"strok C ABI discovery failed: {message}")


def environment_path(name: str) -> Optional[Path]:
    value = os.environ.get(name)
    return Path(value) if value else None


def find_library_directory(prefix: Path) -> Path:
    for directory in (prefix / "lib", prefix / "lib64"):
        if directory.is_dir():
            return directory
    fail(f"no library directory under {prefix}; set STROK_LIBRARY_DIR")


def library_present(directory: Path) -> bool:
    names = (
        "libstrok_c_api.so",
        "libstrok_c_api.dylib",
        "strok_c_api.lib",
        "libstrok_c_api.dll.a",
    )
    return any((directory / name).is_file() for name in names)


def discover_c_api() -> Tuple[Path, Path]:
    prefix = environment_path("STROK_PREFIX")
    include_directory = environment_path("STROK_INCLUDE_DIR")
    library_directory = environment_path("STROK_LIBRARY_DIR")

    if include_directory is None:
        if prefix is None:
            fail("set STROK_PREFIX or both STROK_INCLUDE_DIR and STROK_LIBRARY_DIR")
        include_directory = prefix / "include"
    if library_directory is None:
        if prefix is None:
            fail("set STROK_PREFIX or both STROK_INCLUDE_DIR and STROK_LIBRARY_DIR")
        library_directory = find_library_directory(prefix)

    if not (include_directory / "strok" / "c_api.h").is_file():
        fail(f"missing {include_directory / 'strok' / 'c_api.h'}")
    if not library_directory.is_dir():
        fail(f"library directory does not exist: {library_directory}")
    if not library_present(library_directory):
        fail(f"missing strok_c_api library in {library_directory}")
    return include_directory, library_directory


class BuildStrokExtension(build_ext):
    def build_extensions(self) -> None:
        include_directory, library_directory = discover_c_api()
        for extension in self.extensions:
            extension.include_dirs.append(str(include_directory))
            extension.library_dirs.append(str(library_directory))
            extension.libraries.append("strok_c_api")
            if os.name != "nt":
                extension.runtime_library_dirs.append(str(library_directory))
        super().build_extensions()


setup(
    package_dir={"": "src"},
    packages=["strok"],
    ext_modules=[Extension("strok._strok", [str(ROOT / "src" / "strok" / "module.c")])],
    cmdclass={"build_ext": BuildStrokExtension},
)
