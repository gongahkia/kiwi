#include "cli.hpp"
#include "terminal.hpp"

#include <cstdlib>
#include <iostream>
#include <stdexcept>
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

  if (!contourtty::terminalSessionAvailable()) {
    std::cout << "contourtty " << CONTOURTTY_VERSION << '\n';
    return 0;
  }

  contourtty::resetQuitFlag();
  contourtty::installQuitSignalHandlers();
  contourtty::installResizeSignalHandler();
  contourtty::TerminalSession session;
  if (const char* throw_after_terminal = std::getenv("CONTOURTTY_THROW_AFTER_TERMINAL");
      throw_after_terminal != nullptr && std::string_view(throw_after_terminal) == "1") {
    throw std::runtime_error("forced terminal exception");
  }
  const auto print_size = [] {
    const auto size = contourtty::queryTerminalSize();
    std::cout << "\x1b[Hcontourtty " << CONTOURTTY_VERSION << "\npress q to quit\nsize: "
              << size.cols << 'x' << size.rows << "\n" << std::flush;
  };
  print_size();
  contourtty::consumeResizeFlag();
  while (!contourtty::shouldQuit()) {
    char input = 0;
    const ssize_t n = ::read(STDIN_FILENO, &input, 1);
    if (n == 1 && (input == 'q' || input == 'Q')) {
      break;
    }
    if (contourtty::consumeResizeFlag()) {
      print_size();
    }
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
