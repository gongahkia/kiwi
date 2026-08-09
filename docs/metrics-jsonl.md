# JSON Lines playback metrics

`--metrics-jsonl FILE` writes one JSON object per playback window, normally every second and once more when playback ends. It is independent of `--debug-stats`: metrics collection does not reserve a terminal status row. It applies to terminal playback, not offline export, still snapshots, captions, or media probes. When stdout is not a terminal and strok would otherwise probe media, the option fails instead of silently creating no metrics file.

Every object uses `"schema_version": 1` and `"event": "metrics"`. The common fields are `elapsed_s`, `window_s`, `input_frames`, `presented_frames`, `dropped_frames`, `changed_cells`, `emitted_bytes`, `cpu_percent`, and `rss_bytes`.

Live inputs add `live_producer_replaced`, `live_consumer_discarded`, `live_late_dropped`, `live_write_overruns`, and `live_effective_fps`. `live_decode_to_present_ms_p50`, `p95`, and `p99` describe decoded-frame-to-terminal-present timing. They are not sensor-to-terminal latency. `live_render_ms_*` and `live_write_ms_*` are percentiles for the same rendered live frames. These percentile fields are `null` when the window has no live presentation samples.

Metric samples are capped at 2,048 per window. `live_metric_sample_overflow` makes any truncation explicit. The writer flushes each JSON object, so a completed window remains available during a long-running session.

Example:

```sh
strok --input cam --profile live --metrics-jsonl camera.metrics.jsonl
```

For FFmpeg's own diagnostics, use a separate human-readable log:

```sh
strok --input 'rtsp://camera.example/stream' \
  --log camera.log --ffmpeg-log warning \
  --metrics-jsonl camera.metrics.jsonl
```

FFmpeg messages and regular logs can contain source URLs or server details. Review them before sharing.
