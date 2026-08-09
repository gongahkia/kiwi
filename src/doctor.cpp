#include "doctor.hpp"

#include "gpu_backend.hpp"
#include "gpu_sobel.hpp"
#include "media_input.hpp"
#include "render_graph.hpp"
#include "terminal_caps.hpp"

#include <algorithm>
#include <cstdlib>
#include <exception>
#include <filesystem>
#include <memory>
#include <optional>
#include <set>
#include <sstream>
#include <string>
#include <string_view>
#include <system_error>
#include <utility>

extern "C" {
#include <libavdevice/avdevice.h>
#include <libavformat/avformat.h>
#include <libavutil/avutil.h>
}

namespace strok {
namespace {

std::string boolString(bool value) {
  return value ? "true" : "false";
}

std::string cleanValue(std::string_view value) {
  std::string clean(value);
  std::replace(clean.begin(), clean.end(), '\n', ' ');
  std::replace(clean.begin(), clean.end(), '\r', ' ');
  return clean;
}

std::optional<std::filesystem::path> findProgram(std::string_view program) {
  const char* raw_path = std::getenv("PATH");
  if (raw_path == nullptr || *raw_path == '\0') {
    return std::nullopt;
  }
#if defined(_WIN32)
  constexpr char kPathSeparator = ';';
#else
  constexpr char kPathSeparator = ':';
#endif
  const std::string path(raw_path);
  std::size_t start = 0;
  while (start <= path.size()) {
    const std::size_t end = path.find(kPathSeparator, start);
    const std::string_view entry(path.data() + start, (end == std::string::npos ? path.size() : end) - start);
    const std::filesystem::path directory = entry.empty() ? std::filesystem::current_path() : std::filesystem::path(entry);
    const std::filesystem::path candidate = directory / std::string(program);
    std::error_code error;
    if (std::filesystem::is_regular_file(candidate, error)) {
      return candidate;
    }
#if defined(_WIN32)
    const std::filesystem::path executable = candidate.string() + ".exe";
    error.clear();
    if (std::filesystem::is_regular_file(executable, error)) {
      return executable;
    }
#endif
    if (end == std::string::npos) {
      break;
    }
    start = end + 1;
  }
  return std::nullopt;
}

bool inputProtocolAvailable(std::string_view target) {
  void* opaque = nullptr;
  while (const char* protocol = avio_enum_protocols(&opaque, 0)) {
    if (target == protocol) {
      return true;
    }
  }
  return false;
}

std::string inputDeviceFormats() {
  std::set<std::string> formats;
  const AVInputFormat* format = nullptr;
  while ((format = av_input_video_device_next(format)) != nullptr) {
    if (format->name != nullptr) {
      formats.insert(format->name);
    }
  }
  std::ostringstream out;
  bool first = true;
  for (const std::string& name : formats) {
    if (!first) {
      out << ',';
    }
    out << name;
    first = false;
  }
  return out.str();
}

std::string cameraDeviceAvailability(const CameraInputSpec& camera) {
  if (camera.device.empty()) {
    return "unknown";
  }
  const std::filesystem::path path(camera.device);
  if (!path.is_absolute()) {
    return "unknown";
  }
  std::error_code error;
  if (std::filesystem::exists(path, error)) {
    return "available";
  }
  return error ? "unknown" : "missing";
}

}  // namespace

std::string formatDoctorReport(const CliOptions& options,
                               std::optional<std::filesystem::path> config_path) {
  std::ostringstream out;
  out << "doctor_schema=1\n"
      << "config_source=" << (config_path.has_value() ? config_path->string() : "none") << '\n'
      << "profile=" << options.profile.value_or("none") << '\n';

  out << "[effective_options]\n"
      << "mode=" << options.mode << '\n'
      << "style=" << options.style << '\n'
      << "render_mode=" << options.render_mode << '\n'
      << "max_fps=" << (options.max_fps.has_value() ? std::to_string(*options.max_fps) : "source") << '\n'
      << "fit=" << boolString(options.fit) << '\n'
      << "color_mode=" << options.color_mode << '\n'
      << "dither=" << options.dither << '\n'
      << "reconnect=" << boolString(options.reconnect) << '\n';

  out << "[terminal]\n";
  try {
    const std::optional<std::string> caps_override = options.caps.has_value() && *options.caps != "dump"
                                                         ? options.caps
                                                         : std::nullopt;
    out << formatTerminalCaps(detectTerminalCapsFromEnvironment(options.font_path, caps_override));
  } catch (const std::exception& error) {
    out << "terminal_caps_error=" << cleanValue(error.what()) << '\n';
  }

  out << "[analysis_backend]\n";
  out << "gpu_compiled_backend=" << gpuSobelBackendName() << '\n'
      << "gpu_available=" << boolString(gpuSobelAvailable()) << '\n'
      << "gpu_requested=" << boolString(options.gpu) << '\n';
  try {
    const std::unique_ptr<GpuAnalysisBackend> backend = createGpuAnalysisBackend(options.gpu);
    out << "attempted_backend=" << backendName(backend->attemptedBackend()) << '\n'
        << "active_backend=" << backendName(backend->backend()) << '\n';
  } catch (const std::exception& error) {
    out << "backend_error=" << cleanValue(error.what()) << '\n';
  }

  out << "[ffmpeg]\n";
  const AVInputFormat* rtsp_demuxer = av_find_input_format("rtsp");
  out << "version=" << cleanValue(av_version_info()) << '\n'
      << "license=" << cleanValue(avformat_license()) << '\n'
      << "build_configuration_bytes=" << std::string_view(avformat_configuration()).size() << '\n'
      << "rtsp_demuxer_available=" << boolString(rtsp_demuxer != nullptr) << '\n'
      << "http_protocol_available=" << boolString(inputProtocolAvailable("http")) << '\n'
      << "https_protocol_available=" << boolString(inputProtocolAvailable("https")) << '\n';

  out << "[shader_tools]\n";
  const std::optional<std::filesystem::path> glslang = findProgram("glslangValidator");
  const std::optional<std::filesystem::path> spirv_cross = findProgram("spirv-cross");
  out << "glslangValidator=" << (glslang.has_value() ? glslang->string() : "missing") << '\n'
      << "spirv_cross=" << (spirv_cross.has_value() ? spirv_cross->string() : "missing") << '\n';

  out << "[camera]\n";
  avdevice_register_all();
  const std::optional<CameraInputSpec> camera = cameraInputSpec("cam");
  if (!camera.has_value()) {
    out << "default_format=unsupported\n"
        << "default_device=unsupported\n"
        << "default_device_available=unknown\n"
        << "ffmpeg_input_device_available=false\n";
  } else {
    const AVInputFormat* input_format = av_find_input_format(camera->format.c_str());
    out << "default_format=" << camera->format << '\n'
        << "default_device=" << camera->device << '\n'
        << "default_device_available=" << cameraDeviceAvailability(*camera) << '\n'
        << "ffmpeg_input_device_available=" << boolString(input_format != nullptr) << '\n';
  }
  const std::string formats = inputDeviceFormats();
  out << "ffmpeg_video_input_formats=" << (formats.empty() ? "none" : formats) << '\n';
  return out.str();
}

}  // namespace strok
