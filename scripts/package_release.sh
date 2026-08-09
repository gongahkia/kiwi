#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
build_dir="${STROK_PACKAGE_BUILD_DIR:-"$root/build/package"}"
artifact_dir="${STROK_PACKAGE_OUTPUT_DIR:-"$root"}"
tmp_dir=""

cleanup() {
  if [[ -n "$tmp_dir" ]]; then
    rm -rf "$tmp_dir"
  fi
}
trap cleanup EXIT

cd "$root"

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "missing required command: $1" >&2
    exit 1
  fi
}

require_pkg() {
  if ! pkg-config --exists "$1"; then
    echo "missing pkg-config package: $1" >&2
    exit 1
  fi
}

release_version() {
  local raw="${STROK_PACKAGE_VERSION:-}"
  if [[ -z "$raw" && "${GITHUB_REF_TYPE:-}" == "tag" ]]; then
    raw="${GITHUB_REF_NAME:-}"
  fi
  if [[ -z "$raw" ]]; then
    raw="0.0.0"
  fi
  raw="${raw#v}"
  if [[ ! "$raw" =~ ^[0-9]+(\.[0-9]+){0,3}$ ]]; then
    echo "invalid package version: expected vMAJOR.MINOR.PATCH or numeric CMake version, got ${raw}" >&2
    exit 1
  fi
  printf '%s\n' "$raw"
}

sha256_file() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
    return
  fi
  shasum -a 256 "$1" | awk '{print $1}'
}

require_cmd cmake
require_cmd cpack
require_cmd pkg-config
if ! command -v sha256sum >/dev/null 2>&1; then
  require_cmd shasum
fi
if [[ "$(uname -s)" == "Linux" ]]; then
  require_cmd file
  require_cmd dpkg-shlibdeps
fi
require_pkg libavformat
require_pkg libavcodec
require_pkg libavdevice
require_pkg libavutil
require_pkg libswscale
require_pkg libswresample
require_pkg freetype2

version="$(release_version)"
mkdir -p "$artifact_dir"

cmake -S "$root" -B "$build_dir" \
  -DCMAKE_BUILD_TYPE=Release \
  -DSTROK_VERSION="$version" \
  -DSTROK_WARNINGS_AS_ERRORS=ON
build_args=(--build "$build_dir" --parallel)
if [[ -n "${STROK_PACKAGE_BUILD_JOBS:-}" ]]; then
  build_args=(--build "$build_dir" --parallel "$STROK_PACKAGE_BUILD_JOBS")
fi
cmake "${build_args[@]}"
ctest --test-dir "$build_dir" --output-on-failure

cpack -B "$artifact_dir" --config "$build_dir/CPackConfig.cmake" -G TGZ
package_base="$(sed -n 's/^set(CPACK_PACKAGE_FILE_NAME "\(.*\)")$/\1/p' "$build_dir/CPackConfig.cmake")"
tgz="$artifact_dir/${package_base}.tar.gz"
if [[ ! -f "$tgz" ]]; then
  echo "expected archive was not produced: $tgz" >&2
  exit 1
fi
tmp_dir="$(mktemp -d)"
tar -xzf "$tgz" -C "$tmp_dir"
package_root="$(find "$tmp_dir" -mindepth 1 -maxdepth 1 -type d -print -quit)"
if [[ -z "$package_root" ]]; then
  echo "package root was not found in $tgz" >&2
  exit 1
fi
packaged_bin="$package_root/bin/strok"
if [[ -z "$packaged_bin" ]]; then
  echo "packaged strok binary not found in $tgz" >&2
  exit 1
fi
if [[ ! -x "$packaged_bin" ]]; then
  echo "packaged strok binary is not executable: $packaged_bin" >&2
  exit 1
fi
if [[ "$("$packaged_bin" --version)" != "strok $version" ]]; then
  echo "packaged strok version does not match release version $version" >&2
  exit 1
fi
"$packaged_bin" --help >/dev/null
if [[ ! -f "$package_root/include/strok/c_api.h" ]]; then
  echo "packaged C API header was not found" >&2
  exit 1
fi
packaged_library="$(find "$package_root" -type f \( -name 'libstrok_c_api.so*' -o -name 'libstrok_c_api.dylib' \) -print -quit)"
if [[ -z "$packaged_library" ]]; then
  echo "packaged C API library was not found" >&2
  exit 1
fi
consumer_build="$tmp_dir/c_api_consumer"
cmake -S "$root/tests/c_api_consumer" -B "$consumer_build" -DCMAKE_PREFIX_PATH="$package_root"
cmake --build "$consumer_build" --parallel
packaged_library_dir="$(dirname "$packaged_library")"
if [[ "$(uname -s)" == "Darwin" ]]; then
  DYLD_LIBRARY_PATH="$packaged_library_dir${DYLD_LIBRARY_PATH:+:$DYLD_LIBRARY_PATH}" "$consumer_build/strok_c_api_consumer"
else
  LD_LIBRARY_PATH="$packaged_library_dir${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" "$consumer_build/strok_c_api_consumer"
fi

artifacts=("$tgz")

if [[ "$(uname -s)" == "Linux" ]]; then
  cpack -B "$artifact_dir" --config "$build_dir/CPackConfig.cmake" -G DEB
  deb="$artifact_dir/${package_base}.deb"
  if [[ ! -f "$deb" ]]; then
    echo "expected Debian package was not produced: $deb" >&2
    exit 1
  fi
  if [[ "$(dpkg-deb --field "$deb" Version)" != "$version" ]]; then
    echo "Debian package version does not match release version $version" >&2
    exit 1
  fi
  dpkg-deb --contents "$deb" | grep '/usr/bin/strok$' >/dev/null
  artifacts+=("$deb")
fi

checksum_file="$artifact_dir/${package_base}.sha256"
: >"$checksum_file"
for artifact in "${artifacts[@]}"; do
  printf '%s  %s\n' "$(sha256_file "$artifact")" "$(basename "$artifact")" >>"$checksum_file"
done
echo "packaged version=$version artifacts=${#artifacts[@]} checksums=$(basename "$checksum_file")"
