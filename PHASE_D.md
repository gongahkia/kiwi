# PHASE_D.md — Audio & Sync

**Goal:** Audio playback with the audio track as the master clock, and adaptive frame-skip so video tracks audio instead of drifting. Without this the player looks amateur.

**Exit criteria:** video + audio play in sync to completion, survive pause/seek, and hold sync under load via frame-skip.

---

## §Backend — audio output library
**Recommended: miniaudio** (single-header `miniaudio.h`, MIT, no system dependencies, cross-platform — Windows/macOS/Linux/etc). Alternative: SDL2 audio (heavier dependency but well-trodden). Decision goes in `DEPENDENCIES.md`.

- Open a playback device at a chosen format (e.g. 32-bit float or s16, stereo, 48 kHz) with a callback that pulls from a ring buffer you fill from decoded audio.
- **DoD:** a generated sine wave plays cleanly through the backend (smoke test).

## §AudioDecode — decode + resample the audio stream
- Decode the audio stream with the same send/receive pattern (separate `AVCodecContext` for the audio stream index found in Phase B).
- Resample to the device format with **libswresample** (`swr_alloc_set_opts2` / `swr_convert`) — source channel layout/sample fmt/rate → device layout/fmt/rate.
- Push converted PCM into the playback ring buffer.
- Run audio decode on its own thread (or fold into the decode thread with separate queues). Bounded buffering with back-pressure.
- **DoD:** a clip's audio plays alone with no glitches/underruns.

## §Clock — audio as master clock
- The audio device knows how many frames it has played → current playback time. Maintain `audio_clock_us` = (total samples consumed by device / sample_rate) × 1e6, ideally read from the device's playback cursor for accuracy.
- Expose `int64_t master_clock_us()`.
- **DoD:** returns a real-time-advancing position in microseconds.

## §Sync — video follows audio
- Each loop: read `master_clock_us()`. Choose the video frame whose `pts_us` is closest to (but not far past) the clock.
- If the next queued video frame's pts is **behind** the clock by more than a frame interval → drop it (we're late). If it's **ahead** → wait (sleep) until the clock reaches it.
- Log `drift = video_pts_us - audio_clock_us` periodically.
- **DoD:** |drift| < ~50 ms over a 3-minute clip.

## §Skip — adaptive frame-skip
- When the render+emit can't keep up (decode queue draining, drift growing positive-late), drop video frames to hold sync rather than accumulate lag. This mirrors timg's `TIMG_ALLOW_FRAME_SKIP` behavior.
- Provide `--max-fps N` to cap render rate (decimate) for heavy terminals/SSH.
- Never skip audio; audio is the clock and must stay continuous.
- **DoD:** under artificial load (e.g. tiny terminal at huge resolution), audio stays smooth and video drops frames to keep up; documented.

## §Controls
- Space: pause/resume (pause the audio device AND the render loop together; freeze the clock).
- Left/Right: seek ±N seconds. Seeking requires `av_seek_frame`/`avformat_seek_file` on the format context, then `avcodec_flush_buffers` on both decoders, clear queues and ring buffer, resync clock to the seek target.
- `q` / Ctrl-C: clean quit (Phase A teardown).
- **DoD:** pause holds A/V together; seek lands and stays synced; quit restores terminal.

## §Bench
- Record drift distribution and dropped-frame count for 720p and 1080p in `BENCHMARKS.md`.

## Pitfalls
- Using a wall clock instead of the audio device cursor → slow drift as audio buffer latency accumulates. Read the real playback position.
- Underruns from too-small ring buffer → audio crackle. Size the buffer for your callback period.
- Seeking without flushing decoder buffers → garbage frames / desync.
- Pausing video but not audio (or vice versa) → desync on resume.
- Channel-layout API churn: recent FFmpeg uses `AVChannelLayout` and `swr_alloc_set_opts2`; older uses `swr_alloc_set_opts`. Pin to a version and document.
