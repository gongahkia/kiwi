#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
build_dir="${CONTOURTTY_PACKAGE_BUILD_DIR:-"$root/build/package"}"
tmp_dir=""

cleanup() {
  if [[ -n "$tmp_dir" ]]; then
    rm -rf "$tmp_dir"
  fi
}
trap cleanup EXIT

cd "$root"

cmake -S "$root" -B "$build_dir" \
  -DCMAKE_BUILD_TYPE=Release \
  -DCONTOURTTY_WARNINGS_AS_ERRORS=ON
cmake --build "$build_dir" --parallel
ctest --test-dir "$build_dir" --output-on-failure

cpack --config "$build_dir/CPackConfig.cmake" -G TGZ
package_base="$(sed -n 's/^set(CPACK_PACKAGE_FILE_NAME "\(.*\)")$/\1/p' "$build_dir/CPackConfig.cmake")"
tgz="$root/${package_base}.tar.gz"
tmp_dir="$(mktemp -d)"
tar -xzf "$tgz" -C "$tmp_dir"
packaged_bin="$(find "$tmp_dir" -type f -path "*/bin/contourtty" -print -quit)"
if [[ -z "$packaged_bin" ]]; then
  echo "packaged contourtty binary not found in $tgz" >&2
  exit 1
fi
"$packaged_bin" --version >/dev/null

if [[ "$(uname -s)" == "Linux" ]]; then
  cpack --config "$build_dir/CPackConfig.cmake" -G DEB
fi
