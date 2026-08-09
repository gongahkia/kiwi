#include "auto_mode.hpp"
#include "cli.hpp"
#include "doctor.hpp"
#include "graph_yaml.hpp"
#include "log.hpp"
#include "media_probe.hpp"
#include "player.hpp"
#include "renderer.hpp"
#include "renderer_cli_adapter.hpp"
#include "stream_resolver.hpp"
#include "terminal_caps.hpp"
#include "terminal.hpp"

#include <cstdlib>
#include <iostream>
#include <optional>
#include <stdexcept>
#include <string>
#include <string_view>
#include <unistd.h>

#ifndef STROK_VERSION
#define STROK_VERSION "0.0.0"
#endif

namespace {

int runApp(int argc, char** argv) {
  const auto parsed = strok::parseArgs(argc, argv);
  if (!parsed.error.empty()) {
    std::cerr << parsed.error << '\n';
    return 2;
  }

  if (parsed.action == strok::CliAction::Help) {
    const std::string_view program_name = argc > 0 ? argv[0] : "strok";
    std::cout << strok::helpText(program_name);
    return 0;
  }

  if (parsed.action == strok::CliAction::Version) {
    std::cout << "strok " << STROK_VERSION << '\n';
    return 0;
  }

  strok::CliOptions options = parsed.options;
  if (parsed.action == strok::CliAction::Doctor) {
    std::cout << strok::formatDoctorReport(options, parsed.config_path);
    return 0;
  }
  if (options.graph.has_value() && *options.graph != "dump" && options.graph->find(',') != std::string::npos && !options.split.has_value()) {
    std::cerr << "invalid value for --graph: graph pair requires --split\n";
    return 2;
  }
  if (options.graph.has_value() && *options.graph != "dump" && options.graph->find(',') == std::string::npos) {
    strok::applyGraphYamlToOptions(strok::loadGraphYamlFile(*options.graph), &options);
  }
  strok::Logger logger;
  if (options.log_file.has_value()) {
    logger = strok::Logger(*options.log_file);
    STROK_LOG_INFO(logger, "logger initialized");
  }

  std::optional<strok::TerminalCaps> terminal_caps;
  const auto get_caps = [&]() -> const strok::TerminalCaps& {
    if (!terminal_caps.has_value()) {
      const std::optional<std::string> caps_override = options.caps.has_value() && *options.caps != "dump"
                                                       ? options.caps
                                                       : std::nullopt;
      terminal_caps = strok::detectTerminalCapsFromEnvironment(options.font_path, caps_override);
    }
    return *terminal_caps;
  };

  if (options.caps.has_value() || logger.enabled() || options.mode == "auto") {
    const auto& caps = get_caps();
    STROK_LOG_INFO(logger, "terminal caps " + strok::summarizeTerminalCaps(caps));
    if (options.caps.has_value() && *options.caps == "dump") {
      std::cout << strok::formatTerminalCaps(caps);
      return 0;
    }
  }

  if (options.mode == "auto") {
    resolveAutoMode(&options, get_caps());
    STROK_LOG_INFO(logger, "auto mode resolved to " + options.mode);
  }

  if (options.graph.has_value() && *options.graph == "dump") {
    std::cout << strok::dumpRenderGraph(options);
    return 0;
  }

  if (options.input.has_value()) {
    const std::string original_input = *options.input;
    options.input = strok::resolveMediaInput(original_input);
    if (*options.input != original_input) {
      STROK_LOG_INFO(logger, "resolved input via yt-dlp");
    }
    if (options.export_file.has_value()) {
      return strok::exportMedia(options, logger);
    }
    if (options.still_file.has_value()) {
      return strok::writeStillSnapshot(options, logger);
    }
    if (options.captions_file.has_value()) {
      return strok::writeCaptionSidecar(options, logger);
    }
    const bool diagnostic_probe = options.dump_frame.has_value() || options.dump_png.has_value();
    const bool stdin_playback = *options.input == "stdin";
    if ((stdin_playback || strok::terminalSessionAvailable()) && !diagnostic_probe) {
      return strok::playMedia(options, logger);
    }

    strok::MediaProbeOptions probe_options;
    if (options.dump_frame.has_value()) {
      probe_options.dump_frame_index = *options.dump_frame;
    }
    if (options.dump_png.has_value()) {
      probe_options.dump_png = *options.dump_png;
    }
    if (options.width.has_value()) {
      probe_options.target_cols = *options.width;
    }
    if (options.height.has_value()) {
      probe_options.target_rows = *options.height;
    }
    probe_options.cell_aspect = options.cell_aspect;
    const auto info = strok::probeMedia(*options.input, probe_options);
    std::cout << strok::formatMediaProbeInfo(info);
    return 0;
  }

  if (!strok::terminalSessionAvailable()) {
    STROK_LOG_WARN(logger, "tty unavailable; terminal session skipped");
    std::cout << "strok " << STROK_VERSION << '\n';
    return 0;
  }

  strok::resetQuitFlag();
  strok::installQuitSignalHandlers();
  strok::installResizeSignalHandler();
  strok::TerminalSession session;
  STROK_LOG_INFO(logger, "terminal session started");
  if (const char* throw_after_terminal = std::getenv("STROK_THROW_AFTER_TERMINAL");
      throw_after_terminal != nullptr && std::string_view(throw_after_terminal) == "1") {
    throw std::runtime_error("forced terminal exception");
  }
  const auto print_size = [&logger] {
    const auto size = strok::queryTerminalSize();
    STROK_LOG_INFO(logger, "terminal size " + std::to_string(size.cols) + "x" + std::to_string(size.rows));
    std::cout << "\x1b[Hstrok " << STROK_VERSION << "\npress q to quit\nsize: "
              << size.cols << 'x' << size.rows << "\n" << std::flush;
  };
  print_size();
  strok::consumeResizeFlag();
  while (!strok::shouldQuit()) {
    char input = 0;
    const ssize_t n = ::read(STDIN_FILENO, &input, 1);
    if (n == 1 && (input == 'q' || input == 'Q')) {
      STROK_LOG_INFO(logger, "quit requested by keyboard");
      break;
    }
    if (strok::consumeResizeFlag()) {
      print_size();
    }
  }
  if (strok::shouldQuit()) {
    STROK_LOG_INFO(logger, "quit requested by signal");
  }
  return 0;
}

}  // namespace

int main(int argc, char** argv) {
  try {
    return runApp(argc, argv);
  } catch (const std::exception& error) {
    std::cerr << "fatal: " << error.what() << '\n';
    return 1;
  } catch (...) {
    std::cerr << "fatal: unknown exception\n";
    return 1;
  }
}
