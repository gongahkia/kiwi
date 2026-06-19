#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
build_dir="${CONTOURTTY_PACKAGE_BUILD_DIR:-"$root/build/package"}"

cmake -S "$root" -B "$build_dir" \
  -DCMAKE_BUILD_TYPE=Release \
  -DCONTOURTTY_WARNINGS_AS_ERRORS=ON
cmake --build "$build_dir" --parallel
ctest --test-dir "$build_dir" --output-on-failure

cpack --config "$build_dir/CPackConfig.cmake" -G TGZ
if [[ "$(uname -s)" == "Linux" ]]; then
  cpack --config "$build_dir/CPackConfig.cmake" -G DEB
fi
