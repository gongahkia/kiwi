#pragma once

#include <termios.h>

namespace contourtty {

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
void installQuitSignalHandlers();
bool shouldQuit() noexcept;
void resetQuitFlag() noexcept;

}  // namespace contourtty
