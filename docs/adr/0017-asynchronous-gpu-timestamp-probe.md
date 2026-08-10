# ADR 0017: asynchronous GPU timestamp readback probe

## Status

Accepted for M3 investigation; production instrumentation remains follow-up #108.

## Evidence

Kiwi pins wgpu-native v29.0.1.1. Its checked-in header declares the
`TimestampQuery` feature, pass timestamp writes, query resolve, `MapRead`,
and `wgpuBufferMapAsync` with `AllowProcessEvents` callbacks. Kiwi previously
detected the adapter feature but created only a baseline device, so it could
not issue timestamp work safely.

`make timestamp-probe` creates a separate device with `TimestampQuery`
explicitly required. It records two timestamps around a one-pixel render pass,
resolves them into a `QueryResolve | CopySrc` buffer, copies into a
`MapRead | CopyDst` buffer, and receives the result through an asynchronous
map callback while processing instance events. The probe has a ten-second
diagnostic timeout and releases every temporary device/resource before normal
terminal rendering starts.

On the available Intel Iris Xe / Mesa 25.3.6 Vulkan adapter, the probe
succeeded with a 161-tick pass delta and 2.252 ms asynchronous-map latency.
The latency is adapter-specific; it is not a cross-device performance
comparison. [Inference] The separate probe's normal-rendering overhead is
zero because it is only invoked by `KIWI_TIMESTAMP_PROBE=1` before the frame
loop.

## Decision

Do not make timestamp queries part of normal device creation yet. Adapters
without `TimestampQuery`, device-creation failures, query failures, mapping
failures, and timeout all return explicit `unavailable` diagnostics. The
probe never waits in `Renderer:render`; its bounded wait is restricted to the
explicit development command before any frame is presented.

## Follow-up implementation checklist

1. Request timestamp support only when a user enables instrumentation, with
   a baseline-device fallback when feature device creation fails.
2. Allocate a bounded ring of at least three readback slots, each sized for
   two queries per registered pass.
3. Attach per-pass `WGPUPassTimestampWrites`, resolve/copy after submission,
   and poll completed map callbacks only on later event turns.
4. Publish sample frame latency and explicit unavailable/map-failure states;
   never wait for a query result in the present path.
5. Measure enabled-versus-disabled frame overhead on every supported adapter
   before enabling a production default.
