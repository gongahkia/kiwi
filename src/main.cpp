#include "auto_mode.hpp"
#include "cli.hpp"
#include "graph_yaml.hpp"
#include "log.hpp"
#include "media_probe.hpp"
#include "player.hpp"
#include "renderer.hpp"
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

#ifndef CONTOURTTY_VERSION
#define CONTOURTTY_VERSION "0.0.0"
#endif

namespace {

int runApp(int argc, char** argv) {
  const auto parsed = contourtty::parseArgs(argc, argv);
  if (!parsed.error.empty()) {
    std::cerr << parsed.error << '\n';
    return 2;
  }

  if (parsed.action == contourtty::CliAction::Help) {
    const std::string_view program_name = argc > 0 ? argv[0] : "contourtty";
    std::cout << contourtty::helpText(program_name);
    return 0;
  }

  if (parsed.action == contourtty::CliAction::Version) {
    std::cout << "contourtty " << CONTOURTTY_VERSION << '\n';
    return 0;
  }

  contourtty::CliOptions options = parsed.options;
  if (options.graph.has_value() && *options.graph != "dump") {
    contourtty::applyGraphYamlToOptions(contourtty::loadGraphYamlFile(*options.graph), &options);
  }
  contourtty::Logger logger;
  if (options.log_file.has_value()) {
    logger = contourtty::Logger(*options.log_file);
    CONTOURTTY_LOG_INFO(logger, "logger initialized");
  }

  std::optional<contourtty::TerminalCaps> terminal_caps;
  const auto get_caps = [&]() -> const contourtty::TerminalCaps& {
    if (!terminal_caps.has_value()) {
      const std::optional<std::string> caps_override = options.caps.has_value() && *options.caps != "dump"
                                                       ? options.caps
                                                       : std::nullopt;
      terminal_caps = contourtty::detectTerminalCapsFromEnvironment(options.font_path, caps_override);
    }
    return *terminal_caps;
  };

  if (options.caps.has_value() || logger.enabled() || options.mode == "auto") {
    const auto& caps = get_caps();
    CONTOURTTY_LOG_INFO(logger, "terminal caps " + contourtty::summarizeTerminalCaps(caps));
    if (options.caps.has_value() && *options.caps == "dump") {
      std::cout << contourtty::formatTerminalCaps(caps);
      return 0;
    }
  }

  if (options.mode == "auto") {
    resolveAutoMode(&options, get_caps());
    CONTOURTTY_LOG_INFO(logger, "auto mode resolved to " + options.mode);
  }

  if (options.graph.has_value() && *options.graph == "dump") {
    std::cout << contourtty::dumpRenderGraph(options);
    return 0;
  }

  if (options.input.has_value()) {
    const std::string original_input = *options.input;
    options.input = contourtty::resolveMediaInput(original_input);
    if (*options.input != original_input) {
      CONTOURTTY_LOG_INFO(logger, "resolved input via yt-dlp");
    }
    if (options.export_file.has_value()) {
      return contourtty::exportMedia(options, logger);
    }
    const bool diagnostic_probe = options.dump_frame.has_value() || options.dump_png.has_value();
    if (contourtty::terminalSessionAvailable() && !diagnostic_probe) {
      return contourtty::playMedia(options, logger);
    }

    contourtty::MediaProbeOptions probe_options;
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
    const auto info = contourtty::probeMedia(*options.input, probe_options);
    std::cout << contourtty::formatMediaProbeInfo(info);
    return 0;
  }

  if (!contourtty::terminalSessionAvailable()) {
    CONTOURTTY_LOG_WARN(logger, "tty unavailable; terminal session skipped");
    std::cout << "contourtty " << CONTOURTTY_VERSION << '\n';
    return 0;
  }

  contourtty::resetQuitFlag();
  contourtty::installQuitSignalHandlers();
  contourtty::installResizeSignalHandler();
  contourtty::TerminalSession session;
  CONTOURTTY_LOG_INFO(logger, "terminal session started");
  if (const char* throw_after_terminal = std::getenv("CONTOURTTY_THROW_AFTER_TERMINAL");
      throw_after_terminal != nullptr && std::string_view(throw_after_terminal) == "1") {
    throw std::runtime_error("forced terminal exception");
  }
  const auto print_size = [&logger] {
    const auto size = contourtty::queryTerminalSize();
    CONTOURTTY_LOG_INFO(logger, "terminal size " + std::to_string(size.cols) + "x" + std::to_string(size.rows));
    std::cout << "\x1b[Hcontourtty " << CONTOURTTY_VERSION << "\npress q to quit\nsize: "
              << size.cols << 'x' << size.rows << "\n" << std::flush;
  };
  print_size();
  contourtty::consumeResizeFlag();
  while (!contourtty::shouldQuit()) {
    char input = 0;
    const ssize_t n = ::read(STDIN_FILENO, &input, 1);
    if (n == 1 && (input == 'q' || input == 'Q')) {
      CONTOURTTY_LOG_INFO(logger, "quit requested by keyboard");
      break;
    }
    if (contourtty::consumeResizeFlag()) {
      print_size();
    }
  }
  if (contourtty::shouldQuit()) {
    CONTOURTTY_LOG_INFO(logger, "quit requested by signal");
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
