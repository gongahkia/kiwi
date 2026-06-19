#include "audio_decode.hpp"

#include <array>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <filesystem>
#include <memory>
#include <stdexcept>
#include <string>
#include <string_view>

extern "C" {
#include <libavcodec/avcodec.h>
#include <libavformat/avformat.h>
#include <libavutil/avutil.h>
#include <libavutil/channel_layout.h>
#include <libavutil/samplefmt.h>
#include <libswresample/swresample.h>
}

namespace contourtty {
namespace {

struct FormatContextDeleter {
  void operator()(AVFormatContext* context) const noexcept {
    if (context == nullptr) {
      return;
    }
    AVFormatContext* owned = context;
    avformat_close_input(&owned);
  }
};

using FormatContextPtr = std::unique_ptr<AVFormatContext, FormatContextDeleter>;

struct CodecContextDeleter {
  void operator()(AVCodecContext* context) const noexcept {
    avcodec_free_context(&context);
  }
};

using CodecContextPtr = std::unique_ptr<AVCodecContext, CodecContextDeleter>;

struct PacketDeleter {
  void operator()(AVPacket* packet) const noexcept {
    av_packet_free(&packet);
  }
};

using PacketPtr = std::unique_ptr<AVPacket, PacketDeleter>;

struct FrameDeleter {
  void operator()(AVFrame* frame) const noexcept {
    av_frame_free(&frame);
  }
};

using FramePtr = std::unique_ptr<AVFrame, FrameDeleter>;

struct SwrContextDeleter {
  void operator()(SwrContext* context) const noexcept {
    swr_free(&context);
  }
};

using SwrContextPtr = std::unique_ptr<SwrContext, SwrContextDeleter>;

std::string ffmpegError(int error_code) {
  std::array<char, AV_ERROR_MAX_STRING_SIZE> buffer {};
  if (av_strerror(error_code, buffer.data(), buffer.size()) < 0) {
    return "unknown ffmpeg error";
  }
  return buffer.data();
}

bool looksRemote(std::string_view input) {
  return input.find("://") != std::string_view::npos;
}

CodecContextPtr openAudioDecoder(const AVCodecParameters* codec_parameters) {
  const AVCodec* decoder = avcodec_find_decoder(codec_parameters->codec_id);
  if (decoder == nullptr) {
    throw std::runtime_error("unsupported audio codec: " + std::string(avcodec_get_name(codec_parameters->codec_id)));
  }

  CodecContextPtr codec_context(avcodec_alloc_context3(decoder));
  if (codec_context == nullptr) {
    throw std::runtime_error("failed to allocate audio decoder context");
  }

  int result = avcodec_parameters_to_context(codec_context.get(), codec_parameters);
  if (result < 0) {
    throw std::runtime_error("failed to copy audio decoder parameters: " + ffmpegError(result));
  }

  result = avcodec_open2(codec_context.get(), decoder, nullptr);
  if (result < 0) {
    throw std::runtime_error("failed to open audio decoder: " + std::string(decoder->name) + ": " + ffmpegError(result));
  }

  return codec_context;
}

void resolveInputLayout(AVChannelLayout* layout, const AVCodecContext* codec_context, const AVFrame* frame) {
  if (av_channel_layout_check(&frame->ch_layout) != 0) {
    const int result = av_channel_layout_copy(layout, &frame->ch_layout);
    if (result < 0) {
      throw std::runtime_error("failed to copy frame channel layout: " + ffmpegError(result));
    }
    return;
  }
  if (av_channel_layout_check(&codec_context->ch_layout) != 0) {
    const int result = av_channel_layout_copy(layout, &codec_context->ch_layout);
    if (result < 0) {
      throw std::runtime_error("failed to copy codec channel layout: " + ffmpegError(result));
    }
    return;
  }

  const int channels = frame->ch_layout.nb_channels > 0 ? frame->ch_layout.nb_channels : codec_context->ch_layout.nb_channels;
  if (channels <= 0) {
    throw std::runtime_error("decoded audio has no channel layout");
  }
  av_channel_layout_default(layout, channels);
}

SwrContextPtr createResampler(const AVCodecContext* codec_context, const AVFrame* frame, const AudioDecodeOptions& options) {
  AVChannelLayout input_layout {};
  AVChannelLayout output_layout {};
  resolveInputLayout(&input_layout, codec_context, frame);
  av_channel_layout_default(&output_layout, options.channels);

  SwrContext* raw = nullptr;
  const int result = swr_alloc_set_opts2(
    &raw,
    &output_layout,
    AV_SAMPLE_FMT_FLT,
    options.sample_rate,
    &input_layout,
    static_cast<AVSampleFormat>(frame->format),
    frame->sample_rate,
    0,
    nullptr);
  av_channel_layout_uninit(&input_layout);
  av_channel_layout_uninit(&output_layout);
  if (result < 0) {
    throw std::runtime_error("failed to allocate audio resampler: " + ffmpegError(result));
  }

  SwrContextPtr swr(raw);
  const int init_result = swr_init(swr.get());
  if (init_result < 0) {
    throw std::runtime_error("failed to initialize audio resampler: " + ffmpegError(init_result));
  }
  return swr;
}

void appendConvertedFrame(SwrContext* swr, const AVFrame* frame, const AudioDecodeOptions& options, DecodedAudio* decoded) {
  const int64_t delay = swr_get_delay(swr, frame->sample_rate);
  const int out_capacity = static_cast<int>(av_rescale_rnd(delay + frame->nb_samples, options.sample_rate, frame->sample_rate, AV_ROUND_UP));
  const std::size_t sample_offset = decoded->samples.size();
  decoded->samples.resize(sample_offset + static_cast<std::size_t>(out_capacity) * static_cast<std::size_t>(options.channels));
  uint8_t* output[] = {
    reinterpret_cast<uint8_t*>(decoded->samples.data() + sample_offset),
  };
  const int converted = swr_convert(swr, output, out_capacity, const_cast<const uint8_t**>(frame->extended_data), frame->nb_samples);
  if (converted < 0) {
    throw std::runtime_error("failed to resample audio frame: " + ffmpegError(converted));
  }
  decoded->samples.resize(sample_offset + static_cast<std::size_t>(converted) * static_cast<std::size_t>(options.channels));
}

void drainResampler(SwrContext* swr, int input_sample_rate, const AudioDecodeOptions& options, DecodedAudio* decoded) {
  while (true) {
    const int64_t delay = swr_get_delay(swr, input_sample_rate);
    if (delay <= 0) {
      return;
    }
    const int out_capacity = static_cast<int>(av_rescale_rnd(delay, options.sample_rate, input_sample_rate, AV_ROUND_UP));
    const std::size_t sample_offset = decoded->samples.size();
    decoded->samples.resize(sample_offset + static_cast<std::size_t>(out_capacity) * static_cast<std::size_t>(options.channels));
    uint8_t* output[] = {
      reinterpret_cast<uint8_t*>(decoded->samples.data() + sample_offset),
    };
    const int converted = swr_convert(swr, output, out_capacity, nullptr, 0);
    if (converted < 0) {
      throw std::runtime_error("failed to drain audio resampler: " + ffmpegError(converted));
    }
    decoded->samples.resize(sample_offset + static_cast<std::size_t>(converted) * static_cast<std::size_t>(options.channels));
    if (converted == 0) {
      return;
    }
  }
}

void receiveAudioFrames(AVCodecContext* codec_context, AVFrame* frame, const AudioDecodeOptions& options, DecodedAudio* decoded, SwrContextPtr* swr, int* input_sample_rate) {
  while (true) {
    const int result = avcodec_receive_frame(codec_context, frame);
    if (result == AVERROR(EAGAIN) || result == AVERROR_EOF) {
      return;
    }
    if (result < 0) {
      throw std::runtime_error("failed to receive decoded audio frame: " + ffmpegError(result));
    }

    if (*swr == nullptr) {
      *swr = createResampler(codec_context, frame, options);
      *input_sample_rate = frame->sample_rate;
    }
    appendConvertedFrame(swr->get(), frame, options, decoded);
    ++decoded->decoded_frames;
    av_frame_unref(frame);
  }
}

}  // namespace

DecodedAudio decodeAudioFile(const std::filesystem::path& input, const AudioDecodeOptions& options) {
  av_log_set_level(AV_LOG_QUIET);
  if (options.sample_rate <= 0) {
    throw std::runtime_error("audio output sample rate must be positive");
  }
  if (options.channels <= 0) {
    throw std::runtime_error("audio output channel count must be positive");
  }

  const std::string input_string = input.string();
  if (!looksRemote(input_string)) {
    std::error_code stat_error;
    if (!std::filesystem::exists(input, stat_error)) {
      throw std::runtime_error("missing file: " + input_string);
    }
    if (!std::filesystem::is_regular_file(input, stat_error)) {
      throw std::runtime_error("not a regular file: " + input_string);
    }
    if (std::filesystem::file_size(input, stat_error) == 0 && !stat_error) {
      throw std::runtime_error("empty file: " + input_string);
    }
  }

  AVFormatContext* raw_context = nullptr;
  int result = avformat_open_input(&raw_context, input_string.c_str(), nullptr, nullptr);
  if (result < 0) {
    throw std::runtime_error("could not open media for audio: " + input_string + ": " + ffmpegError(result));
  }
  FormatContextPtr format_context(raw_context);

  result = avformat_find_stream_info(format_context.get(), nullptr);
  if (result < 0) {
    throw std::runtime_error("could not read audio stream info: " + input_string + ": " + ffmpegError(result));
  }

  int audio_stream_index = -1;
  for (unsigned int i = 0; i < format_context->nb_streams; ++i) {
    const AVStream* stream = format_context->streams[i];
    if (stream != nullptr && stream->codecpar != nullptr &&
        stream->codecpar->codec_type == AVMEDIA_TYPE_AUDIO) {
      audio_stream_index = static_cast<int>(i);
      break;
    }
  }
  if (audio_stream_index < 0) {
    throw NoAudioStreamError("no audio stream found: " + input_string);
  }

  const AVStream* audio_stream = format_context->streams[audio_stream_index];
  const auto codec_context = openAudioDecoder(audio_stream->codecpar);
  PacketPtr packet(av_packet_alloc());
  if (packet == nullptr) {
    throw std::runtime_error("failed to allocate audio packet");
  }
  FramePtr frame(av_frame_alloc());
  if (frame == nullptr) {
    throw std::runtime_error("failed to allocate audio frame");
  }

  DecodedAudio decoded;
  decoded.sample_rate = options.sample_rate;
  decoded.channels = options.channels;
  SwrContextPtr swr;
  int input_sample_rate = codec_context->sample_rate > 0 ? codec_context->sample_rate : options.sample_rate;

  while (true) {
    const int read_result = av_read_frame(format_context.get(), packet.get());
    if (read_result == AVERROR_EOF) {
      break;
    }
    if (read_result < 0) {
      throw std::runtime_error("failed to read audio packet: " + ffmpegError(read_result));
    }
    if (packet->stream_index == audio_stream_index) {
      int send_result = avcodec_send_packet(codec_context.get(), packet.get());
      if (send_result == AVERROR(EAGAIN)) {
        receiveAudioFrames(codec_context.get(), frame.get(), options, &decoded, &swr, &input_sample_rate);
        send_result = avcodec_send_packet(codec_context.get(), packet.get());
      }
      if (send_result < 0) {
        av_packet_unref(packet.get());
        throw std::runtime_error("failed to send audio packet: " + ffmpegError(send_result));
      }
      receiveAudioFrames(codec_context.get(), frame.get(), options, &decoded, &swr, &input_sample_rate);
    }
    av_packet_unref(packet.get());
  }

  result = avcodec_send_packet(codec_context.get(), nullptr);
  if (result < 0 && result != AVERROR_EOF) {
    throw std::runtime_error("failed to drain audio decoder: " + ffmpegError(result));
  }
  receiveAudioFrames(codec_context.get(), frame.get(), options, &decoded, &swr, &input_sample_rate);
  if (swr != nullptr) {
    drainResampler(swr.get(), input_sample_rate, options, &decoded);
  }

  const uint64_t total_frames = static_cast<uint64_t>(decoded.samples.size() / static_cast<std::size_t>(decoded.channels));
  decoded.duration_us = static_cast<int64_t>(std::llround(static_cast<double>(total_frames) * 1000000.0 / static_cast<double>(decoded.sample_rate)));
  return decoded;
}

}  // namespace contourtty
