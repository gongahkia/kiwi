#include "terminal.hpp"

#include <array>
#include <csignal>
#include <cstdlib>
#include <iostream>
#include <string_view>

#include <unistd.h>

namespace {

void expect(bool condition, const char* label) {
  if (!condition) {
    std::cerr << label << '\n';
    std::exit(1);
  }
}

}  // namespace

int main() {
  {
    int pipe_fds[2] {};
    expect(::pipe(pipe_fds) == 0, "terminal output pipe opens");
    constexpr std::string_view expected = "terminal bytes";
    expect(strok::writeTerminalAll(pipe_fds[1], expected), "terminal output writes complete buffer");
    std::array<char, expected.size()> actual {};
    expect(::read(pipe_fds[0], actual.data(), actual.size()) == static_cast<ssize_t>(actual.size()),
           "terminal output reads complete buffer");
    expect(std::string_view(actual.data(), actual.size()) == expected, "terminal output preserves bytes");
    ::close(pipe_fds[0]);
    ::close(pipe_fds[1]);
  }
  expect(!strok::writeTerminalAll(-1, "x"), "terminal output reports invalid descriptor");

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
