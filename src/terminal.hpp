#pragma once

#include <termios.h>

#include <string_view>

namespace strok {

struct TerminalSize {
  int cols = 0;
  int rows = 0;
  int xpixel = 0;
  int ypixel = 0;
};

class TerminalSession {
 public:
  TerminalSession();
  TerminalSession(const TerminalSession&) = delete;
  TerminalSession& operator=(const TerminalSession&) = delete;
  TerminalSession(TerminalSession&&) = delete;
  TerminalSession& operator=(TerminalSession&&) = delete;
  ~TerminalSession() noexcept;

  void restore() noexcept;

 private:
  termios original_{};
  bool active_ = false;
};

bool terminalSessionAvailable() noexcept;
bool writeTerminalAll(int fd, std::string_view bytes) noexcept;
TerminalSize queryTerminalSize();
void installQuitSignalHandlers();
void installResizeSignalHandler();
bool shouldQuit() noexcept;
void resetQuitFlag() noexcept;
bool consumeResizeFlag() noexcept;

}  // namespace strok
