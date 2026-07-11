#include "terminal.hpp"

#include <cerrno>
#include <csignal>
#include <stdexcept>
#include <string>
#include <sys/ioctl.h>
#include <unistd.h>

namespace strok {
namespace {

volatile std::sig_atomic_t g_should_quit = 0;
volatile std::sig_atomic_t g_was_resized = 1;

void handleQuitSignal(int) {
  g_should_quit = 1;
}

void handleResizeSignal(int) {
  g_was_resized = 1;
}

bool writeAll(int fd, const char* data, std::size_t size) noexcept {
  std::size_t written = 0;
  while (written < size) {
    const ssize_t n = ::write(fd, data + written, size - written);
    if (n < 0) {
      if (errno == EINTR) {
        continue;
      }
      return false;
    }
    written += static_cast<std::size_t>(n);
  }
  return true;
}

}  // namespace

TerminalSession::TerminalSession() {
  if (!terminalSessionAvailable()) {
    throw std::runtime_error("terminal session requires tty stdin/stdout");
  }
  if (::tcgetattr(STDIN_FILENO, &original_) != 0) {
    throw std::runtime_error("tcgetattr failed");
  }

  termios raw = original_;
  raw.c_lflag &= static_cast<unsigned>(~(ECHO | ICANON | IEXTEN));
  raw.c_iflag &= static_cast<unsigned>(~(IXON | ICRNL));
  raw.c_cc[VMIN] = 0;
  raw.c_cc[VTIME] = 1;

  if (::tcsetattr(STDIN_FILENO, TCSAFLUSH, &raw) != 0) {
    throw std::runtime_error("tcsetattr raw mode failed");
  }

  constexpr const char* enter = "\x1b[?1049h\x1b[?25l";
  if (!writeAll(STDOUT_FILENO, enter, std::char_traits<char>::length(enter))) {
    ::tcsetattr(STDIN_FILENO, TCSAFLUSH, &original_);
    throw std::runtime_error("failed to enter terminal alternate screen");
  }
  active_ = true;
}

TerminalSession::~TerminalSession() noexcept {
  restore();
}

void TerminalSession::restore() noexcept {
  if (!active_) {
    return;
  }
  constexpr const char* leave = "\x1b[?25h\x1b[?1049l";
  writeAll(STDOUT_FILENO, leave, std::char_traits<char>::length(leave));
  ::tcsetattr(STDIN_FILENO, TCSAFLUSH, &original_);
  active_ = false;
}

bool terminalSessionAvailable() noexcept {
  return ::isatty(STDIN_FILENO) != 0 && ::isatty(STDOUT_FILENO) != 0;
}

TerminalSize queryTerminalSize() {
  winsize size {};
  if (::ioctl(STDOUT_FILENO, TIOCGWINSZ, &size) != 0) {
    throw std::runtime_error("terminal size query failed");
  }
  return TerminalSize{
    .cols = static_cast<int>(size.ws_col),
    .rows = static_cast<int>(size.ws_row),
    .xpixel = static_cast<int>(size.ws_xpixel),
    .ypixel = static_cast<int>(size.ws_ypixel),
  };
}

void installQuitSignalHandlers() {
  struct sigaction action {};
  action.sa_handler = handleQuitSignal;
  sigemptyset(&action.sa_mask);
  action.sa_flags = 0;
  sigaction(SIGINT, &action, nullptr);
  sigaction(SIGTERM, &action, nullptr);
  sigaction(SIGHUP, &action, nullptr);
}

void installResizeSignalHandler() {
  struct sigaction action {};
  action.sa_handler = handleResizeSignal;
  sigemptyset(&action.sa_mask);
  action.sa_flags = 0;
  sigaction(SIGWINCH, &action, nullptr);
}

bool shouldQuit() noexcept {
  return g_should_quit != 0;
}

void resetQuitFlag() noexcept {
  g_should_quit = 0;
}

bool consumeResizeFlag() noexcept {
  if (g_was_resized == 0) {
    return false;
  }
  g_was_resized = 0;
  return true;
}

}  // namespace strok
