#include "cli.hpp"
#include "log.hpp"
#include "media_probe.hpp"
#include "player.hpp"
#include "terminal.hpp"

#include <cstdlib>
#include <iostream>
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

  contourtty::Logger logger;
  if (parsed.options.log_file.has_value()) {
    logger = contourtty::Logger(*parsed.options.log_file);
    CONTOURTTY_LOG_INFO(logger, "logger initialized");
  }

  if (parsed.options.input.has_value()) {
    const bool diagnostic_probe = parsed.options.dump_frame.has_value() || parsed.options.dump_png.has_value();
    if (contourtty::terminalSessionAvailable() && !diagnostic_probe) {
      return contourtty::playMedia(parsed.options, logger);
    }

    contourtty::MediaProbeOptions probe_options;
    if (parsed.options.dump_frame.has_value()) {
      probe_options.dump_frame_index = *parsed.options.dump_frame;
    }
    if (parsed.options.dump_png.has_value()) {
      probe_options.dump_png = *parsed.options.dump_png;
    }
    if (parsed.options.width.has_value()) {
      probe_options.target_cols = *parsed.options.width;
    }
    if (parsed.options.height.has_value()) {
      probe_options.target_rows = *parsed.options.height;
    }
    probe_options.cell_aspect = parsed.options.cell_aspect;
    const auto info = contourtty::probeMedia(*parsed.options.input, probe_options);
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
