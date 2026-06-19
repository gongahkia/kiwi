# BENCHMARKS.md

Record reproducible decode/render measurements here as phases add real media work.

| Date | Commit | Machine | OS | Source | Cols x rows | Mode | Color | Sustained fps | Bytes/frame | Command | Notes |
|---|---|---|---|---|---:|---|---|---:|---:|---|---|
| 2026-06-19 | B8 commit | arm64; CPU brand unavailable (`sysctl` denied) | macOS 26.5.1 | generated 30-frame 1920x1080 h264 testsrc | 160 x 45 | decode+downscale probe | RGB24 | 1298.064 | n/a | `./build/ci/contourtty --width 160 /tmp/contourtty-b8-1080p.mp4` | no render; output `decode_seconds: 0.023111`, `decoded_frames: 30` |
