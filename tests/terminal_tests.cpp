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
  strok::resetQuitFlag();
  expect(!strok::shouldQuit(), "quit flag starts clear");

  strok::installQuitSignalHandlers();
  std::raise(SIGINT);
  expect(strok::shouldQuit(), "SIGINT sets quit flag");
  strok::resetQuitFlag();
  expect(!strok::shouldQuit(), "quit flag resets");

  strok::installResizeSignalHandler();
  (void)strok::consumeResizeFlag();
  expect(!strok::consumeResizeFlag(), "resize flag drains");
  std::raise(SIGWINCH);
  expect(strok::consumeResizeFlag(), "SIGWINCH sets resize flag");
  expect(!strok::consumeResizeFlag(), "resize flag drains after SIGWINCH");
}
