#include "terminal.hpp"

#include <csignal>
#include <cstdlib>
#include <iostream>

namespace {

void expect(bool condition, const char* label) {
  if (!condition) {
    std::cerr << label << '\n';
    std::exit(1);
  }
}

}  // namespace

int main() {
  contourtty::resetQuitFlag();
  expect(!contourtty::shouldQuit(), "quit flag starts clear");

  contourtty::installQuitSignalHandlers();
  std::raise(SIGINT);
  expect(contourtty::shouldQuit(), "SIGINT sets quit flag");
  contourtty::resetQuitFlag();
  expect(!contourtty::shouldQuit(), "quit flag resets");

  contourtty::installResizeSignalHandler();
  (void)contourtty::consumeResizeFlag();
  expect(!contourtty::consumeResizeFlag(), "resize flag drains");
  std::raise(SIGWINCH);
  expect(contourtty::consumeResizeFlag(), "SIGWINCH sets resize flag");
  expect(!contourtty::consumeResizeFlag(), "resize flag drains after SIGWINCH");
}
