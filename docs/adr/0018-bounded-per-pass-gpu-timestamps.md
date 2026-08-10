# ADR 0018: bounded per-pass GPU timestamps

## Status

Accepted for M3.

## Decision

GPU timestamp instrumentation is opt-in through `KIWI_GPU_TIMESTAMPS=1`.
Kiwi requests `TimestampQuery` when it creates the renderer device; if the
adapter lacks the feature or feature-device creation fails, it creates the
baseline device and records an explicit unavailable reason. Normal startup
does not request the feature.

When enabled, Kiwi allocates one query set with two query indexes per actual
GPU pass and three fixed readback slots. Each frame obtains a free slot, adds
pass timestamp writes, resolves all queries after encoding, and copies them to
a map-read buffer. It starts `wgpuBufferMapAsync` only after queue submission.
Later `wgpuInstanceProcessEvents` turns poll a completed slot; no present path
waits for a query result. A full ring drops only that frame's measurement and
increments a bounded counter.

Results use stable built-in pass names, frame number, GPU tick delta, and CPU
map latency. Tick values are deliberately not converted to milliseconds: the
pinned binding does not expose a timestamp-period conversion. Histories retain
at most 120 completed frames. Surface resizing reconfigures presentation but
does not recreate the device resources behind the query ring. Renderer teardown
releases those resources before context/device teardown and requests
cancellation for pending map reads in a bounded native cleanup path.

## Validation evidence

`make gpu-timing-smoke` on the available Intel Iris Xe / Mesa 25.3.6 Vulkan
adapter reported delayed samples for `terminal/background`, `terminal/glyph`,
and `terminal/cursor`, with one pending readback and no dropped measurement
frames. The observed map latency (195.080 ms in that run) is an asynchronous
result delay, not a frame stall or a portable performance claim.
