# Live Input Acceptance

This is an opt-in host acceptance path for live camera and RTSP playback. It is not part of the default CTest suite: it needs a pseudo-terminal, FFmpeg, `timeout`, and either Docker on Linux or a supplied RTSP endpoint. It records decoded-frame-to-present timing, not physical sensor-to-terminal latency.

Run the disposable no-audio RTSP fixture on Linux:

```sh
cmake --build build/ci --target live_input_acceptance
```

The target starts an isolated MediaMTX server using `bluenviron/mediamtx:1` with host networking, publishes a 30 fps no-audio FFmpeg `testsrc2` stream, and reads it through both TCP and UDP RTSP transports. MediaMTX documents this image and its host-networking requirement, while its FFmpeg guide documents RTSP publishing with FFmpeg. See <https://mediamtx.org/docs/kickoff/install> and <https://mediamtx.org/docs/publish/ffmpeg>.

The run has two traces per transport. The pressure trace uses `STROK_TEST_WRITE_DELAY_MS=120` to model a slow terminal acceptance path; the capped trace sets `--fps 30 --max-fps 5`. Both use `--debug-stats`, a deterministic 80x24 PTY, a 3 second live open/read timeout, and reconnect backoff. The harness requires nonzero queue replacement or consumer skip and a write overrun in the pressure trace. It requires `live_effective_fps=5.0` in the capped trace. This exercises no-audio live scheduling without claiming a universal end-to-end latency bound.

Set `STROK_LIVE_ACCEPTANCE_OUTPUT` to retain a known result directory. Otherwise the script prints a newly created temporary directory. Each trace writes:

- `.env`: source (with RTSP credentials redacted), command parameters, binary version, kernel, and FFmpeg version;
- `.log`: unmodified strok diagnostics;
- `.metrics`: one key-value debug sample per line, suitable for later JSONL/metrics ingestion;
- `.typescript`: the PTY transcript.

Use a physical or V4L2-loopback camera separately; never add a hardware device to the default test suite:

```sh
STROK_CAMERA_INPUT=v4l2:/dev/video0 \
STROK_LIVE_ACCEPTANCE_OUTPUT=/tmp/strok-camera-proof \
scripts/verify_live_inputs.sh build/ci/strok camera
```

For a remote RTSP source, provide the URL through the environment rather than placing credentials in a command history. The generated metadata redacts `user:password@`, but the raw source log should still be treated as potentially sensitive and reviewed before sharing.

```sh
STROK_RTSP_URL='rtsp://user:password@camera.example/stream' \
STROK_LIVE_ACCEPTANCE_SOURCE_CADENCE='30fps (camera setting)' \
STROK_LIVE_ACCEPTANCE_OUTPUT=/tmp/strok-remote-rtsp-proof \
scripts/verify_live_inputs.sh build/ci/strok rtsp
```

Attach a complete physical-camera trace and a complete remote-RTSP trace to [issue #95](https://github.com/gongahkia/strok/issues/95). Record terminal model/version, transport, source cadence, connection topology, and whether the source contains audio. Run the terminal graphics evidence separately for [issue #13](https://github.com/gongahkia/strok/issues/13), and preserve backend lifecycle/repeated-render evidence for [issue #94](https://github.com/gongahkia/strok/issues/94). A local RTSP fixture is controlled protocol evidence; it is not a substitute for either of those host traces.
