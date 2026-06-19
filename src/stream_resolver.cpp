#include "stream_resolver.hpp"

#include <array>
#include <cerrno>
#include <cstdlib>
#include <cstring>
#include <stdexcept>
#include <string>
#include <string_view>
#include <sys/wait.h>
#include <unistd.h>

namespace contourtty {
namespace {

std::string firstNonEmptyLine(std::string_view output) {
  std::size_t start = 0;
  while (start < output.size()) {
    std::size_t end = output.find('\n', start);
    if (end == std::string_view::npos) {
      end = output.size();
    }
    std::string_view line = output.substr(start, end - start);
    while (!line.empty() && (line.back() == '\r' || line.back() == ' ' || line.back() == '\t')) {
      line.remove_suffix(1);
    }
    while (!line.empty() && (line.front() == ' ' || line.front() == '\t')) {
      line.remove_prefix(1);
    }
    if (!line.empty()) {
      return std::string(line);
    }
    start = end + 1;
  }
  return {};
}

std::string ytDlpExecutable() {
  if (const char* override = std::getenv("CONTOURTTY_YTDLP"); override != nullptr && override[0] != '\0') {
    return override;
  }
  return "yt-dlp";
}

std::string resolveWithYtDlp(std::string_view input) {
  int pipefd[2] {};
  if (pipe(pipefd) != 0) {
    throw std::runtime_error("yt-dlp pipe failed: " + std::string(std::strerror(errno)));
  }

  const std::string executable = ytDlpExecutable();
  const std::string url(input);
  const pid_t child = fork();
  if (child < 0) {
    close(pipefd[0]);
    close(pipefd[1]);
    throw std::runtime_error("yt-dlp fork failed: " + std::string(std::strerror(errno)));
  }
  if (child == 0) {
    close(pipefd[0]);
    dup2(pipefd[1], STDOUT_FILENO);
    close(pipefd[1]);
    execlp(executable.c_str(), executable.c_str(), "-g", "--no-playlist", "-f", "best", url.c_str(), static_cast<char*>(nullptr));
    _exit(errno == ENOENT ? 127 : 126);
  }

  close(pipefd[1]);
  std::string output;
  std::array<char, 4096> buffer {};
  while (true) {
    const ssize_t n = read(pipefd[0], buffer.data(), buffer.size());
    if (n > 0) {
      output.append(buffer.data(), static_cast<std::size_t>(n));
      continue;
    }
    if (n == 0) {
      break;
    }
    if (errno == EINTR) {
      continue;
    }
    close(pipefd[0]);
    throw std::runtime_error("yt-dlp read failed: " + std::string(std::strerror(errno)));
  }
  close(pipefd[0]);

  int status = 0;
  while (waitpid(child, &status, 0) < 0) {
    if (errno == EINTR) {
      continue;
    }
    throw std::runtime_error("yt-dlp wait failed: " + std::string(std::strerror(errno)));
  }
  if (WIFEXITED(status) && WEXITSTATUS(status) == 127) {
    throw std::runtime_error("yt-dlp is required for YouTube URLs; install yt-dlp or pass a direct media URL");
  }
  if (!WIFEXITED(status) || WEXITSTATUS(status) != 0) {
    throw std::runtime_error("yt-dlp failed to resolve URL");
  }

  const std::string resolved = firstNonEmptyLine(output);
  if (resolved.empty()) {
    throw std::runtime_error("yt-dlp returned no media URL");
  }
  return resolved;
}

}  // namespace

bool isUrlInput(std::string_view input) noexcept {
  return input.find("://") != std::string_view::npos;
}

bool requiresYtDlp(std::string_view input) noexcept {
  return input.find("youtube.com/") != std::string_view::npos ||
         input.find("youtu.be/") != std::string_view::npos;
}

std::string resolveMediaInput(std::string_view input) {
  if (!isUrlInput(input) || !requiresYtDlp(input)) {
    return std::string(input);
  }
  return resolveWithYtDlp(input);
}

}  // namespace contourtty
