#include "shader_compiler.hpp"

#include "shader_source.hpp"

#include <array>
#include <cerrno>
#include <cstring>
#include <fstream>
#include <sstream>
#include <string_view>

#ifdef _WIN32
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>
#else
#include <sys/wait.h>
#include <unistd.h>
#endif

namespace strok {
namespace {

unsigned long processId() noexcept {
#ifdef _WIN32
  return GetCurrentProcessId();
#else
  return static_cast<unsigned long>(getpid());
#endif
}

class TempDir {
 public:
  explicit TempDir(const std::optional<std::filesystem::path>& base) {
    const std::filesystem::path root = base.value_or(std::filesystem::temp_directory_path());
    for (int attempt = 0; attempt < 100; ++attempt) {
      std::filesystem::path candidate = root / ("strok-shader-" + std::to_string(processId()) + "-" + std::to_string(attempt));
      std::error_code ec;
      if (std::filesystem::create_directory(candidate, ec)) {
        path_ = std::move(candidate);
        return;
      }
    }
    throw ShaderCompileError("failed to create shader temp directory");
  }

  ~TempDir() {
    if (!path_.empty()) {
      std::error_code ec;
      std::filesystem::remove_all(path_, ec);
    }
  }

  const std::filesystem::path& path() const noexcept {
    return path_;
  }

 private:
  std::filesystem::path path_;
};

std::vector<std::uint8_t> readBinary(const std::filesystem::path& path) {
  std::ifstream input(path, std::ios::binary);
  if (!input) {
    throw ShaderCompileError("failed to read shader output: " + path.string());
  }
  return std::vector<std::uint8_t>(std::istreambuf_iterator<char>(input), std::istreambuf_iterator<char>());
}

std::string readText(const std::filesystem::path& path) {
  std::ifstream input(path);
  if (!input) {
    throw ShaderCompileError("failed to read shader output: " + path.string());
  }
  std::ostringstream buffer;
  buffer << input.rdbuf();
  return buffer.str();
}

void writeBinary(const std::filesystem::path& path, std::span<const std::uint8_t> bytes) {
  std::ofstream output(path, std::ios::binary);
  if (!output) {
    throw ShaderCompileError("failed to write shader input: " + path.string());
  }
  output.write(reinterpret_cast<const char*>(bytes.data()), static_cast<std::streamsize>(bytes.size()));
  if (!output) {
    throw ShaderCompileError("failed to write shader input: " + path.string());
  }
}

void writeText(const std::filesystem::path& path, std::string_view text) {
  std::ofstream output(path);
  if (!output) {
    throw ShaderCompileError("failed to write shader input: " + path.string());
  }
  output << text;
  if (!output) {
    throw ShaderCompileError("failed to write shader input: " + path.string());
  }
}

std::string commandLabel(const std::vector<std::string>& args) {
  std::ostringstream out;
  for (std::size_t i = 0; i < args.size(); ++i) {
    if (i > 0) {
      out << ' ';
    }
    out << args[i];
  }
  return out.str();
}

#ifdef _WIN32
std::string windowsErrorMessage(DWORD code) {
  char* message = nullptr;
  const DWORD flags = FORMAT_MESSAGE_ALLOCATE_BUFFER | FORMAT_MESSAGE_FROM_SYSTEM | FORMAT_MESSAGE_IGNORE_INSERTS;
  const DWORD size = FormatMessageA(flags, nullptr, code, 0, reinterpret_cast<LPSTR>(&message), 0, nullptr);
  std::string result = size > 0 && message != nullptr ? std::string(message, size) : "error " + std::to_string(code);
  if (message != nullptr) {
    LocalFree(message);
  }
  while (!result.empty() && (result.back() == '\r' || result.back() == '\n')) {
    result.pop_back();
  }
  return result;
}

void appendWindowsQuotedArg(std::string& command, const std::string& arg) {
  if (!command.empty()) {
    command.push_back(' ');
  }
  command.push_back('"');
  std::size_t backslashes = 0;
  for (char c : arg) {
    if (c == '\\') {
      ++backslashes;
      continue;
    }
    if (c == '"') {
      command.append(backslashes * 2 + 1, '\\');
      command.push_back('"');
      backslashes = 0;
      continue;
    }
    command.append(backslashes, '\\');
    backslashes = 0;
    command.push_back(c);
  }
  command.append(backslashes * 2, '\\');
  command.push_back('"');
}

std::string windowsCommandLine(const std::vector<std::string>& args) {
  std::string command;
  for (const std::string& arg : args) {
    appendWindowsQuotedArg(command, arg);
  }
  return command;
}

void runToolWindows(const std::vector<std::string>& args) {
  SECURITY_ATTRIBUTES security {};
  security.nLength = sizeof(security);
  security.bInheritHandle = TRUE;

  HANDLE read_pipe = nullptr;
  HANDLE write_pipe = nullptr;
  if (!CreatePipe(&read_pipe, &write_pipe, &security, 0)) {
    throw ShaderCompileError("shader tool pipe failed: " + windowsErrorMessage(GetLastError()));
  }
  if (!SetHandleInformation(read_pipe, HANDLE_FLAG_INHERIT, 0)) {
    const DWORD error = GetLastError();
    CloseHandle(read_pipe);
    CloseHandle(write_pipe);
    throw ShaderCompileError("shader tool pipe failed: " + windowsErrorMessage(error));
  }

  STARTUPINFOA startup {};
  startup.cb = sizeof(startup);
  startup.dwFlags = STARTF_USESTDHANDLES;
  startup.hStdInput = GetStdHandle(STD_INPUT_HANDLE);
  startup.hStdOutput = write_pipe;
  startup.hStdError = write_pipe;

  PROCESS_INFORMATION process {};
  std::string command = windowsCommandLine(args);
  if (!CreateProcessA(nullptr, command.data(), nullptr, nullptr, TRUE, CREATE_NO_WINDOW, nullptr, nullptr, &startup, &process)) {
    const DWORD error = GetLastError();
    CloseHandle(read_pipe);
    CloseHandle(write_pipe);
    throw ShaderCompileError("shader tool failed: " + commandLabel(args) + ": " + windowsErrorMessage(error));
  }

  CloseHandle(write_pipe);
  std::string output;
  std::array<char, 4096> buffer {};
  while (true) {
    DWORD n = 0;
    const BOOL read_ok = ReadFile(read_pipe, buffer.data(), static_cast<DWORD>(buffer.size()), &n, nullptr);
    if (read_ok) {
      if (n == 0) {
        break;
      }
      output.append(buffer.data(), n);
      continue;
    }
    const DWORD error = GetLastError();
    if (error == ERROR_BROKEN_PIPE) {
      break;
    }
    CloseHandle(read_pipe);
    TerminateProcess(process.hProcess, 1);
    CloseHandle(process.hThread);
    CloseHandle(process.hProcess);
    throw ShaderCompileError("shader tool read failed: " + windowsErrorMessage(error));
  }
  CloseHandle(read_pipe);

  WaitForSingleObject(process.hProcess, INFINITE);
  DWORD exit_code = 1;
  if (!GetExitCodeProcess(process.hProcess, &exit_code)) {
    const DWORD error = GetLastError();
    CloseHandle(process.hThread);
    CloseHandle(process.hProcess);
    throw ShaderCompileError("shader tool wait failed: " + windowsErrorMessage(error));
  }
  CloseHandle(process.hThread);
  CloseHandle(process.hProcess);
  if (exit_code == 0) {
    return;
  }

  std::ostringstream error;
  error << "shader tool failed: " << commandLabel(args) << " exit=" << exit_code;
  if (!output.empty()) {
    error << ": " << output.substr(0, 2048);
  }
  throw ShaderCompileError(error.str());
}
#else
void runToolPosix(const std::vector<std::string>& args) {
  int pipefd[2] {};
  if (pipe(pipefd) != 0) {
    throw ShaderCompileError("shader tool pipe failed: " + std::string(std::strerror(errno)));
  }

  const pid_t child = fork();
  if (child < 0) {
    close(pipefd[0]);
    close(pipefd[1]);
    throw ShaderCompileError("shader tool fork failed: " + std::string(std::strerror(errno)));
  }
  if (child == 0) {
    close(pipefd[0]);
    dup2(pipefd[1], STDOUT_FILENO);
    dup2(pipefd[1], STDERR_FILENO);
    close(pipefd[1]);
    std::vector<char*> argv;
    argv.reserve(args.size() + 1);
    for (const std::string& arg : args) {
      argv.push_back(const_cast<char*>(arg.c_str()));
    }
    argv.push_back(nullptr);
    execvp(argv[0], argv.data());
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
    throw ShaderCompileError("shader tool read failed: " + std::string(std::strerror(errno)));
  }
  close(pipefd[0]);

  int status = 0;
  while (waitpid(child, &status, 0) < 0) {
    if (errno == EINTR) {
      continue;
    }
    throw ShaderCompileError("shader tool wait failed: " + std::string(std::strerror(errno)));
  }
  if (WIFEXITED(status) && WEXITSTATUS(status) == 0) {
    return;
  }

  std::ostringstream error;
  error << "shader tool failed: " << commandLabel(args);
  if (WIFEXITED(status)) {
    error << " exit=" << WEXITSTATUS(status);
  } else {
    error << " abnormal-exit";
  }
  if (!output.empty()) {
    error << ": " << output.substr(0, 2048);
  }
  throw ShaderCompileError(error.str());
}
#endif

void runTool(const std::vector<std::string>& args) {
  if (args.empty()) {
    throw ShaderCompileError("empty shader tool command");
  }
#ifdef _WIN32
  runToolWindows(args);
#else
  runToolPosix(args);
#endif
}

}  // namespace

std::string_view shaderStageFlag(ShaderStage stage) noexcept {
  switch (stage) {
    case ShaderStage::Vertex:
      return "vert";
    case ShaderStage::Fragment:
      return "frag";
    case ShaderStage::Compute:
      return "comp";
  }
  return "frag";
}

std::vector<std::uint8_t> compileGlslToSpirv(const std::filesystem::path& source, const ShaderCompileOptions& options) {
  if (!std::filesystem::is_regular_file(source)) {
    throw ShaderCompileError("shader source not found: " + source.string());
  }
  TempDir temp(options.work_dir);
  const std::filesystem::path spirv_path = temp.path() / "shader.spv";
  runTool({
    options.tools.glslang_validator.string(),
    "-V",
    "-S",
    std::string(shaderStageFlag(options.stage)),
    "-e",
    options.entry_point,
    "-o",
    spirv_path.string(),
    source.string(),
  });
  std::vector<std::uint8_t> spirv = readBinary(spirv_path);
  if (spirv.empty()) {
    throw ShaderCompileError("glslangValidator produced empty SPIR-V");
  }
  return spirv;
}

std::vector<std::uint8_t> compileGlslSourceToSpirv(std::string_view source, const ShaderCompileOptions& options) {
  if (source.empty()) {
    throw ShaderCompileError("empty GLSL source");
  }
  TempDir temp(options.work_dir);
  const std::filesystem::path source_path = temp.path() / "shader.glsl";
  writeText(source_path, source);
  return compileGlslToSpirv(source_path, options);
}

std::string compileSpirvToMsl(std::span<const std::uint8_t> spirv, const ShaderCompileOptions& options) {
  if (spirv.empty()) {
    throw ShaderCompileError("empty SPIR-V input");
  }
  TempDir temp(options.work_dir);
  const std::filesystem::path spirv_path = temp.path() / "shader.spv";
  const std::filesystem::path msl_path = temp.path() / "shader.msl";
  writeBinary(spirv_path, spirv);
  runTool({
    options.tools.spirv_cross.string(),
    spirv_path.string(),
    "--msl",
    "--output",
    msl_path.string(),
  });
  std::string msl = readText(msl_path);
  if (msl.empty()) {
    throw ShaderCompileError("spirv-cross produced empty MSL");
  }
  return msl;
}

ShaderCompileResult compileGlslToSpirvAndMsl(const std::filesystem::path& source, const ShaderCompileOptions& options) {
  ShaderCompileResult result;
  result.spirv = compileGlslToSpirv(source, options);
  result.msl = compileSpirvToMsl(result.spirv, options);
  return result;
}

ShaderCompileResult compileShadertoyFragmentToSpirvAndMsl(std::string_view source, const ShaderCompileOptions& options) {
  const std::string wrapped_source = wrapShadertoyFragmentShader(source);
  ShaderCompileResult result;
  result.spirv = compileGlslSourceToSpirv(wrapped_source, options);
  result.msl = compileSpirvToMsl(result.spirv, options);
  return result;
}

}  // namespace strok
