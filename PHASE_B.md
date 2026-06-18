# PHASE_B.md — Decode & Frame Pipeline

**Goal:** Turn any local media file into a stream of RGB frames at the correct grid resolution, using the modern libav send/receive API, on a worker thread feeding a bounded queue.

**Exit criteria:** common files (mp4/mkv/webm) decode to correctly-scaled RGB frames at known fps, threaded, leak-free under ASan, with the circle test passing.

---

## The modern libav decode flow (use this, not the deprecated one)

The old `avcodec_decode_video2` is deprecated. Use the send/receive API:

```
avformat_open_input            -> open container, read header
avformat_find_stream_info      -> populate stream info
(find video stream index via AVMEDIA_TYPE_VIDEO)
avcodec_find_decoder           -> get AVCodec for the stream's codec_id
avcodec_alloc_context3         -> allocate AVCodecContext
avcodec_parameters_to_context  -> copy codecpar into the context
avcodec_open2                  -> open the decoder

loop:
  av_read_frame(fmt, pkt)              -> read one AVPacket
  if pkt.stream_index == videoStream:
     avcodec_send_packet(ctx, pkt)
     while avcodec_receive_frame(ctx, frame) == 0:
         sws_scale(...)                -> convert to RGB24 into our buffer
         emit Frame
  av_packet_unref(pkt)

drain: avcodec_send_packet(ctx, NULL); then receive until AVERROR_EOF
```

`avcodec_receive_frame` returns `AVERROR(EAGAIN)` when it needs more input (send another packet) and `AVERROR_EOF` at end of stream. Handle both explicitly.

## §Open
- `avformat_open_input(&fmt, path, nullptr, nullptr)`; on failure print a specific error (file not found vs not a media file — use `av_strerror`).
- `avformat_find_stream_info`.
- Walk `fmt->streams[0..nb_streams)`, pick first with `codecpar->codec_type == AVMEDIA_TYPE_VIDEO`; remember the audio stream index too (Phase D).
- `av_dump_format` to the log in debug mode.
- **DoD:** prints codec name, WxH, pix_fmt, duration (from `fmt->duration`), avg fps (from stream `avg_frame_rate`).

## §Decoder
- `avcodec_find_decoder(codecpar->codec_id)`; error if null ("unsupported codec").
- `avcodec_alloc_context3` + `avcodec_parameters_to_context` + `avcodec_open2`.
- Consider `ctx->thread_count = 0` (auto) and `thread_type` for multithreaded decode of heavy codecs.
- **DoD:** no deprecated calls; decoder opens for h264/hevc/vp9 test clips.

## §DecodeLoop
- Implement the send/receive loop above.
- **DoD:** decodes every frame of a known-length clip; frame count matches expectation; correct EAGAIN/EOF handling; drains at end.

## §Convert
- Create one `SwsContext` once you know source WxH and pix_fmt:
  `sws_getContext(srcW, srcH, srcFmt, dstW, dstH, AV_PIX_FMT_RGB24, SWS_BILINEAR, ...)`.
- **Important:** the destination size here can be the *grid working resolution* (see §Aspect) so swscale does the heavy downscaling efficiently in one step, rather than decoding full-res then scaling separately. Decide: scale to grid res directly in swscale (faster) vs scale to full RGB then downsample (simpler). Recommend **scale directly to working resolution** in swscale for performance; recreate the context if the grid size changes (on resize).
- Reuse output buffers (`av_image_fill_arrays` into a persistent buffer, or manage your own).
- **DoD:** dump frame ~100 to PNG; it visually matches the source.

## §Frame
```cpp
struct Frame {
    int w = 0, h = 0;             // working resolution (grid-related), not source res
    std::vector<uint8_t> rgb;     // w*h*3, RGB24
    int64_t pts_us = 0;           // presentation time, microseconds
};
```
- Clear ownership; move-only or shared_ptr in the queue.
- **DoD:** ASan-clean over a full-clip decode.

## §Aspect — correct-aspect downscale to grid (the quality canary)

Terminal cells are taller than wide (≈ 1:2 width:height). If you sample on a square grid the output looks vertically stretched.

Given target `cols` (from CLI or terminal width) and `cell_aspect = cell_w / cell_h` (default 0.5):

```
img_aspect = src_w / src_h
rows = round( cols * (1/img_aspect) * cell_aspect )
```

i.e. compress vertical cell count by the cell's height-to-width ratio so a circle stays a circle. If both `cols` and `rows` are bounded by terminal size, fit to the smaller constraint and recompute the other.

If using §Convert's direct-scale approach, the swscale destination is then:
- structure/luminance single-sample-per-cell modes: dst = `cols × rows` (one pixel per cell), OR
- structure mode that needs sub-cell detail: dst = `cols*S × rows*S` for some supersample/cell-region factor S (Phase E needs the sub-region; plan for S≥4 vertically, ~2 horizontally to capture shape).

**Plan now:** make the working resolution `cols*cellPxW × rows*cellPxH` where `cellPxW×cellPxH` is the per-cell sample block (e.g. 2×4 or 4×8). Luminance mode averages the block; structure mode analyzes it. This single decision serves both modes.

- **DoD:** circle source renders circular at default cell_aspect; documented formula.

## §PTS — timing metadata
- `pts_us = frame->pts * av_q2d(stream->time_base) * 1e6` (guard `AV_NOPTS_VALUE`; fall back to frame index / fps).
- **DoD:** monotonic increasing on a normal clip.

## §Threading
- Decoder runs on a worker thread; pushes `Frame`s into a bounded queue (capacity 4–8) with a condition variable; blocks when full (back-pressure).
- Main/render thread pops frames.
- Clean shutdown: signal stop, drain/abort, join thread; no leaks.
- **DoD:** bounded memory; clean join; no deadlock on early quit.

## §Bench
- Decode+downscale-only loop (no render) → frames/sec on a 1080p clip. Record machine + numbers in `BENCHMARKS.md`. This is your decode ceiling; rendering can't exceed it.

## §Errors
- corrupt file, missing file, audio-only file, zero-byte file → specific non-crashing messages.

## Pitfalls
- Recreating `SwsContext` per frame (huge waste) — create once, recreate only on size change.
- Ignoring `AVERROR(EAGAIN)` and treating it as an error.
- Forgetting to drain the decoder at EOF (you lose the last few frames).
- Not handling `AV_NOPTS_VALUE` → broken sync later.
- Assuming source is RGB; it's usually YUV420P — always convert.
