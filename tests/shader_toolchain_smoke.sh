#!/usr/bin/env bash
set -euo pipefail

if ! command -v glslangValidator >/dev/null 2>&1; then
  echo "glslangValidator unavailable; skipping shader toolchain smoke"
  exit 77
fi
if ! command -v spirv-cross >/dev/null 2>&1; then
  echo "spirv-cross unavailable; skipping shader toolchain smoke"
  exit 77
fi

tmp="${TMPDIR:-/tmp}/contourtty-shader-toolchain-$$"
rm -rf "$tmp"
mkdir -p "$tmp"
trap 'rm -rf "$tmp"' EXIT

shader="$tmp/smoke.frag"
spirv="$tmp/smoke.spv"
msl="$tmp/smoke.msl"

cat >"$shader" <<'GLSL'
#version 450
layout(location = 0) out vec4 fragColor;
void main() {
  fragColor = vec4(1.0, 0.0, 1.0, 1.0);
}
GLSL

glslangValidator -V -S frag -e main -o "$spirv" "$shader"
test -s "$spirv"
spirv-cross "$spirv" --msl --output "$msl"
test -s "$msl"
