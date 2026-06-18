#include "cli.hpp"

#include <iostream>
#include <string_view>

#ifndef CONTOURTTY_VERSION
#define CONTOURTTY_VERSION "0.0.0"
#endif

int main(int argc, char** argv) {
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

  std::cout << "contourtty " << CONTOURTTY_VERSION << '\n';
  return 0;
}
