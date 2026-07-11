#!/usr/bin/env python3
import argparse
import csv
import os
import re
import shlex
import statistics
import subprocess
from dataclasses import dataclass
from pathlib import Path


@dataclass(frozen=True)
class Case:
  key: str
  mode_label: str
  color: str
  args: tuple[str, ...]


@dataclass(frozen=True)
class Source:
  label: str
  size: str
  cols: int
  rows: int
  path: Path


CASES = (
  Case("luminance", "luminance", "mono", ("--mode", "luminance", "--color-mode", "mono")),
  Case("structure-hog", "structure-HoG", "mono", ("--mode", "structure", "--glyph-features", "hog", "--color-mode", "mono")),
  Case("structure-sdf", "structure-SDF", "mono", ("--mode", "structure", "--glyph-features", "sdf", "--color-mode", "mono")),
  Case("octant", "octant", "truecolor", ("--mode", "octant", "--color-mode", "truecolor")),
  Case("sextant", "sextant", "truecolor", ("--mode", "sextant", "--color-mode", "truecolor")),
  Case("halfblock", "halfblock", "truecolor", ("--mode", "halfblock", "--color-mode", "truecolor")),
  Case("braille", "braille", "truecolor", ("--mode", "braille", "--color-mode", "truecolor")),
  Case("blocks", "blocks", "truecolor", ("--mode", "blocks", "--color-mode", "truecolor")),
  Case("hatch", "hatch", "truecolor", ("--style", "hatch", "--color-mode", "truecolor")),
  Case("stipple", "stipple", "truecolor", ("--style", "stipple", "--color-mode", "truecolor")),
  Case("painterly", "painterly", "truecolor", ("--style", "painterly", "--color-mode", "truecolor")),
  Case("flow", "flow", "truecolor", ("--style", "flow", "--color-mode", "truecolor")),
  Case("pixel-kitty", "pixel-Kitty", "truecolor", ("--render-mode", "pixel", "--caps", "kitty", "--color-mode", "truecolor")),
)


def run_checked(command: list[str], **kwargs) -> subprocess.CompletedProcess:
  proc = subprocess.run(command, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, **kwargs)
  if proc.returncode != 0:
    raise RuntimeError(
      "command failed\n"
      + " ".join(shlex.quote(part) for part in command)
      + "\nstdout:\n"
      + proc.stdout[-4000:]
      + "\nstderr:\n"
      + proc.stderr[-4000:]
    )
  return proc


def first_existing_font() -> str | None:
  for path in (
    "/System/Library/Fonts/SFNSMono.ttf",
    "/System/Library/Fonts/Menlo.ttc",
    "/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf",
    "/usr/share/fonts/dejavu-sans-mono-fonts/DejaVuSansMono.ttf",
  ):
    if Path(path).exists():
      return path
  return None


def ensure_fixture(path: Path, size: str, frames: int) -> None:
  path.parent.mkdir(parents=True, exist_ok=True)
  run_checked([
    "ffmpeg",
    "-hide_banner",
    "-loglevel",
    "error",
    "-y",
    "-f",
    "lavfi",
    "-i",
    f"testsrc2=duration=1:size={size}:rate={frames}",
    "-frames:v",
    str(frames),
    "-pix_fmt",
    "yuv420p",
    str(path),
  ])


def parse_time(stderr: str) -> tuple[float, float, float]:
  values: dict[str, float] = {}
  for line in stderr.splitlines():
    match = re.match(r"^(real|user|sys) ([0-9.]+)$", line.strip())
    if match:
      values[match.group(1)] = float(match.group(2))
  if not {"real", "user", "sys"} <= set(values):
    raise RuntimeError(f"missing /usr/bin/time output: {stderr}")
  return values["real"], values["user"], values["sys"]


def parse_log(path: Path) -> tuple[int, int, int, str]:
  text = path.read_text()
  match = re.search(r"render stats frames=(\d+) cells=(\d+) render_us=(\d+)", text)
  if not match:
    raise RuntimeError(f"missing render stats in {path}")
  backend_note = "cpu"
  if "gpu analysis requested; using Metal" in text:
    backend_note = "metal"
  elif "gpu analysis requested; Metal unavailable" in text or "gpu analysis requested; using CPU" in text:
    backend_note = "cpu-fallback"
  elif "render mode pixel protocol=kitty" in text:
    backend_note = "kitty-protocol"
  return int(match.group(1)), int(match.group(2)), int(match.group(3)), backend_note


def median(values: list[float]) -> float:
  return statistics.median(values)


def spread_pct(values: list[float]) -> float:
  mid = median(values)
  if mid == 0:
    return 0.0
  return max(abs(value - mid) / mid for value in values) * 100.0


def command_for(binary: Path, source: Source, case: Case, backend: str, font: str | None, output: Path, log: Path) -> list[str]:
  command = [
    str(binary),
    "--width",
    str(source.cols),
    "--height",
    str(source.rows),
    "--fps",
    "1000",
    "--export",
    str(output),
    "--log",
    str(log),
  ]
  if backend == "gpu":
    command.append("--gpu")
  command.extend(case.args)
  if case.key in {"structure-hog", "structure-sdf"} and font is not None:
    command.extend(["--font", font])
  if case.key in {"structure-hog", "structure-sdf", "hatch", "flow"}:
    command.extend(["--edge-threshold", "0.02", "--dog-sigma", "0", "--glyph-stickiness", "0"])
  command.append(str(source.path))
  return command


def run_case(binary: Path, source: Source, case: Case, backend: str, repeats: int, warmups: int, work: Path, font: str | None, workers: int | None) -> dict[str, object]:
  case_dir = work / "runs" / source.label / backend / case.key
  case_dir.mkdir(parents=True, exist_ok=True)
  env = os.environ.copy()
  command_prefix = ""
  if workers is not None:
    env["STROK_WORKERS"] = str(workers)
    command_prefix = f"STROK_WORKERS={workers} "
  for index in range(warmups):
    output = case_dir / f"warmup-{index}.ansi"
    log = case_dir / f"warmup-{index}.log"
    command = command_for(binary, source, case, backend, font, output, log)
    run_checked(["/usr/bin/time", "-p", *command], env=env)

  rows = []
  command_text = ""
  for index in range(repeats):
    output = case_dir / f"run-{index}.ansi"
    log = case_dir / f"run-{index}.log"
    command = command_for(binary, source, case, backend, font, output, log)
    command_text = command_prefix + " ".join(shlex.quote(part) for part in command)
    timed = run_checked(["/usr/bin/time", "-p", *command], env=env)
    real, user, sys = parse_time(timed.stderr)
    frames, cells, render_us, backend_note = parse_log(log)
    rows.append({
      "real": real,
      "user": user,
      "sys": sys,
      "frames": frames,
      "cells": cells,
      "render_us": render_us,
      "bytes": output.stat().st_size,
      "backend_note": backend_note,
    })

  real_values = [float(row["real"]) for row in rows]
  render_values = [float(row["render_us"]) for row in rows]
  byte_values = [float(row["bytes"]) for row in rows]
  frame_values = [int(row["frames"]) for row in rows]
  median_frames = int(median([float(value) for value in frame_values]))
  return {
    "source": source.label,
    "source_size": source.size,
    "cols_rows": f"{source.cols} x {source.rows}",
    "mode": case.mode_label,
    "backend": backend,
    "backend_note": ",".join(sorted(set(str(row["backend_note"]) for row in rows))),
    "color": case.color,
    "frames": median_frames,
    "fps": median_frames / median(real_values),
    "bytes_per_frame": median(byte_values) / median_frames,
    "render_us": median(render_values),
    "render_spread_pct": spread_pct(render_values),
    "real_spread_pct": spread_pct(real_values),
    "command": command_text,
  }


def markdown_table(rows: list[dict[str, object]], threshold: float, repeats: int, frames: int, workers: int | None) -> str:
  worker_note = f" with `STROK_WORKERS={workers}`" if workers is not None else ""
  lines = [
    f"Generated by `scripts/final_benchmark_sweep.py --repeats {repeats} --frames {frames}`{worker_note}.",
    f"Repeatability is max deviation from median `render_us` across {repeats} measured runs; threshold {threshold:.1f}%.",
    "",
    "| Source | Mode | Backend | Backend note | Cols x rows | Color | Frames | Median fps | Bytes/frame | Median render_us | render_us spread | Command |",
    "|---|---|---|---|---:|---|---:|---:|---:|---:|---:|---|",
  ]
  for row in rows:
    lines.append(
      "| {source} | {mode} | {backend} | {backend_note} | {cols_rows} | {color} | {frames} | {fps:.3f} | {bytes_per_frame:.2f} | {render_us:.0f} | {render_spread_pct:.2f}% | `{command}` |".format(**row)
    )
  return "\n".join(lines) + "\n"


def write_csv(path: Path, rows: list[dict[str, object]]) -> None:
  with path.open("w", newline="") as handle:
    writer = csv.DictWriter(handle, fieldnames=list(rows[0].keys()))
    writer.writeheader()
    writer.writerows(rows)


def load_failed_keys(path: Path, threshold: float) -> set[tuple[str, str, str]]:
  keys: set[tuple[str, str, str]] = set()
  with path.open(newline="") as handle:
    for row in csv.DictReader(handle):
      if float(row["render_spread_pct"]) > threshold:
        keys.add((row["source"], row["mode"], row["backend"]))
  return keys


def selected(source: Source, case: Case, backend: str, args: argparse.Namespace, failed_keys: set[tuple[str, str, str]]) -> bool:
  if args.only_failed_from is not None and (source.label, case.mode_label, backend) not in failed_keys:
    return False
  if args.only_source and source.label not in args.only_source:
    return False
  if args.only_case and case.key not in args.only_case and case.mode_label not in args.only_case:
    return False
  if args.only_backend and backend not in args.only_backend:
    return False
  return True


def main() -> None:
  parser = argparse.ArgumentParser()
  parser.add_argument("--binary", default="build/package/strok")
  parser.add_argument("--work", default="/tmp/strok-p8-final")
  parser.add_argument("--out", default="/tmp/strok-p8-final/P8_FINAL_BENCHMARKS.md")
  parser.add_argument("--repeats", type=int, default=3)
  parser.add_argument("--warmups", type=int, default=1)
  parser.add_argument("--frames", type=int, default=12)
  parser.add_argument("--threshold-pct", type=float, default=10.0)
  parser.add_argument("--workers", type=int)
  parser.add_argument("--only-source", action="append", choices=("720p", "1080p"))
  parser.add_argument("--only-case", action="append")
  parser.add_argument("--only-backend", action="append", choices=("cpu", "gpu"))
  parser.add_argument("--only-failed-from", type=Path)
  args = parser.parse_args()

  binary = Path(args.binary)
  if not binary.exists():
    raise SystemExit(f"missing binary: {binary}")
  work = Path(args.work)
  work.mkdir(parents=True, exist_ok=True)
  sources = (
    Source("720p", "1280x720", 160, 45, work / "input-720p.mp4"),
    Source("1080p", "1920x1080", 240, 90, work / "input-1080p.mp4"),
  )
  for source in sources:
    ensure_fixture(source.path, source.size, args.frames)

  font = first_existing_font()
  failed_keys = load_failed_keys(args.only_failed_from, args.threshold_pct) if args.only_failed_from is not None else set()
  rows = []
  for source in sources:
    for case in CASES:
      for backend in ("cpu", "gpu"):
        if not selected(source, case, backend, args, failed_keys):
          continue
        row = run_case(binary, source, case, backend, args.repeats, args.warmups, work, font, args.workers)
        print(f"{row['source']} {row['mode']} {backend}: render spread {row['render_spread_pct']:.2f}%")
        rows.append(row)
  if not rows:
    raise SystemExit("no rows selected")

  failures = [row for row in rows if float(row["render_spread_pct"]) > args.threshold_pct]
  out = Path(args.out)
  out.parent.mkdir(parents=True, exist_ok=True)
  out.write_text(markdown_table(rows, args.threshold_pct, args.repeats, args.frames, args.workers))
  write_csv(out.with_suffix(".csv"), rows)
  if failures:
    labels = ", ".join(f"{row['source']} {row['mode']} {row['backend']}={row['render_spread_pct']:.2f}%" for row in failures)
    raise SystemExit(f"repeatability threshold failed: {labels}")


if __name__ == "__main__":
  main()
