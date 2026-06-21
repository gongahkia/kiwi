#!/usr/bin/env bash
set -euo pipefail

bin="${1:-./build/ci/contourtty}"
out="${2:-docs/contourtty.1}"
version="$("$bin" --version | awk '{print $2}')"
date_text="${CONTOURTTY_MAN_DATE:-$(date -u +%Y-%m-%d)}"

mkdir -p "$(dirname "$out")"
{
  printf '.TH CONTOURTTY 1 "%s" "contourtty %s" "User Commands"\n' "$date_text" "$version"
  printf '.SH NAME\n'
  printf 'contourtty \\- structure-aware ASCII terminal media renderer\n'
  printf '.SH SYNOPSIS\n'
  printf '.B contourtty\n'
  printf '[options] [input]\n'
  printf '.SH DESCRIPTION\n'
  printf 'contourtty renders local files, images, GIFs, streams, and camera inputs\n'
  printf 'as terminal ASCII.\n'
  printf 'Structure mode chooses glyphs from edge orientation and shape instead of\n'
  printf 'brightness alone.\n'
  printf 'When audio is present, audio playback provides the master clock.\n'
  printf '.SH OPTIONS\n'
  printf '.nf\n'
  "$bin" --help | sed '1d'
  printf '.fi\n'
  printf '.SH CONFIGURATION\n'
  printf 'Defaults are read from $XDG_CONFIG_HOME/contourtty/config, or\n'
  printf '~/.config/contourtty/config when XDG_CONFIG_HOME is unset.\n'
  printf 'The file uses key=value entries matching long flag names without leading dashes.\n'
  printf 'Command-line flags override config values.\n'
  printf '.SH EXAMPLES\n'
  printf '.nf\n'
  printf 'contourtty --mode structure movie.mp4\n'
  printf 'contourtty --width 120 --height 40 --color-mode 256 stream.m3u8\n'
  printf 'contourtty --export out.mp4 --mode structure movie.mp4\n'
  printf 'contourtty --export out.cast --mode structure movie.mp4\n'
  printf '.fi\n'
  printf '.SH FILES\n'
  printf '.I ~/.config/contourtty/config\n'
  printf '.SH SEE ALSO\n'
  printf 'ffmpeg(1), asciinema(1)\n'
} >"$out"
