local bit = require("bit")
local ffi = require("ffi")
local ShellMetadata = require("kiwi.terminal.shell_integration")

ffi.cdef[[
typedef struct { unsigned short ws_row; unsigned short ws_col; unsigned short ws_xpixel; unsigned short ws_ypixel; } KiwiWinsize;
int forkpty(int* amaster, char* name, const void* termp, const KiwiWinsize* winp);
void _exit(int status);
int close(int fd);
int chdir(const char* path);
int gethostname(char* name, unsigned long length);
long read(int fd, void* buffer, unsigned long count);
long write(int fd, const void* buffer, unsigned long count);
int waitpid(int pid, int* status, int options);
int kill(int pid, int sig);
extern char **environ;
int usleep(unsigned int usec);
int kiwi_pty_resize(int fd, unsigned short columns, unsigned short rows);
int kiwi_pty_set_nonblocking(int fd);
int kiwi_execvpe(const char* file, char* const argv[], char* const envp[]);
]]

local root = os.getenv("KIWI_ROOT") or "."
local library_extension = ffi.os == "OSX" and ".dylib" or ".so"
local native_path = os.getenv("KIWI_SURFACE_LIB") or root .. "/.build/native/libkiwi_surface" .. library_extension
local native_ok, native = pcall(ffi.load, native_path)
if not native_ok then
  error("Unable to load Kiwi native bridge at " .. native_path .. "; run make native: " .. tostring(native))
end

local util_ok, util
if ffi.os == "OSX" then
  util_ok, util = pcall(ffi.load, "System")
else
  util_ok, util = pcall(ffi.load, "util")
  if not util_ok then util_ok, util = pcall(ffi.load, "libutil.so.1") end
end
if not util_ok then
  error("Unable to load libutil for forkpty: " .. tostring(util))
end

local Pty = {}
Pty.__index = Pty
Pty.maximum_working_directory_bytes = 2048

local constants = {
  eagain = ffi.os == "OSX" and 35 or 11,
  eintr = 4,
  eio = 5,
  wnohang = 1,
  sighup = 1,
  sigterm = 15,
  sigkill = 9,
}

local function errno_message(prefix)
  return string.format("%s: errno %d", prefix, ffi.errno())
end

local function validate_command(command)
  assert(type(command) == "table" and #command > 0, "PTY command must contain an executable")
  for index, argument in ipairs(command) do
    assert(type(argument) == "string" and not argument:find("\0", 1, true), "PTY argument " .. index .. " must be a NUL-free string")
  end
end

local function validate_working_directory(options)
  if options == nil then return nil end
  assert(type(options) == "table", "PTY options must be a table")
  local cwd = options.cwd
  if cwd == nil then return nil end
  assert(type(cwd) == "string" and #cwd <= Pty.maximum_working_directory_bytes and cwd:sub(1, 1) == "/" and not cwd:find("\0", 1, true), "PTY working directory must be an absolute NUL-free path no longer than 2048 bytes")
  return cwd
end

local function build_environment(overrides)
  local entries = {}
  local positions = {}
  local source = ffi.C.environ
  local index = 0
  while source[index] ~= nil do
    local entry = ffi.string(source[index])
    local separator = entry:find("=", 1, true)
    local name = separator and entry:sub(1, separator - 1) or entry
    local position = positions[name]
    if position then
      entries[position] = entry
    else
      positions[name] = #entries + 1
      entries[#entries + 1] = entry
    end
    index = index + 1
  end
  for name, value in pairs(overrides) do
    local position = positions[name]
    if value == false then
      if position then entries[position] = false end
    elseif position then
      entries[position] = name .. "=" .. value
    else
      positions[name] = #entries + 1
      entries[#entries + 1] = name .. "=" .. value
    end
  end

  local count = 0
  for _, entry in ipairs(entries) do
    if entry then count = count + 1 end
  end
  local environment = ffi.new("char *[?]", count + 1)
  local buffers = {}
  local output = 0
  for _, entry in ipairs(entries) do
    if entry then
      local buffer = ffi.new("char[?]", #entry + 1)
      ffi.copy(buffer, entry)
      buffers[#buffers + 1] = buffer
      environment[output] = buffer
      output = output + 1
    end
  end
  return environment, buffers
end

function Pty.default_command()
  local shell = os.getenv("SHELL")
  if shell and shell:sub(1, 1) == "/" and not shell:find("\0", 1, true) then
    return { shell }
  end
  return { "/bin/sh" }
end

function Pty.spawn(command, columns, rows, environment, options)
  validate_command(command)
  assert(columns > 0 and rows > 0 and columns <= 65535 and rows <= 65535, "PTY dimensions must fit winsize")
  environment = environment or {}
  local cwd = validate_working_directory(options)
  for name, value in pairs(environment) do
    assert(name:match("^[A-Za-z_][A-Za-z0-9_]*$") and (value == false or (type(value) == "string" and not value:find("\0", 1, true))), "invalid PTY environment entry")
  end

  local argv = ffi.new("char *[?]", #command + 1)
  for index, argument in ipairs(command) do
    argv[index - 1] = ffi.cast("char *", argument)
  end
  local child_environment, child_environment_buffers = build_environment(environment)
  local master = ffi.new("int[1]")
  local size = ffi.new("KiwiWinsize", { ws_row = rows, ws_col = columns })
  local pid = util.forkpty(master, nil, nil, size)
  if pid < 0 then
    error(errno_message("forkpty"))
  end
  if pid == 0 then
    if cwd ~= nil then ffi.C.chdir(cwd) end
    native.kiwi_execvpe(argv[0], argv, child_environment)
    ffi.C._exit(127)
  end

  if native.kiwi_pty_set_nonblocking(master[0]) ~= 0 then
    local message = errno_message("fcntl O_NONBLOCK")
    ffi.C.close(master[0])
    ffi.C.kill(-pid, constants.sighup)
    error(message)
  end
  return setmetatable({
    fd = master[0],
    pid = pid,
    read_buffer = ffi.new("uint8_t[8192]"),
    pending = "",
    pending_offset = 1,
    eof = false,
    exited = false,
    exit_status = nil,
    bytes_read = 0,
    bytes_written = 0,
    last_read_bytes = 0,
    last_read_calls = 0,
  }, Pty)
end

function Pty.local_hostname()
  local buffer = ffi.new("char[256]")
  if ffi.C.gethostname(buffer, 256) ~= 0 then return nil end
  local raw = ffi.string(buffer, 256)
  local terminator = raw:find("\0", 1, true)
  if terminator == nil or terminator == 1 then return nil end
  local hostname = raw:sub(1, terminator - 1)
  return hostname
end

function Pty.local_working_directory(directory)
  return ShellMetadata.local_path(directory, Pty.local_hostname())
end

function Pty:read_available(max_bytes)
  if self.fd == nil or self.eof then
    self.last_read_bytes = 0
    self.last_read_calls = 0
    return ""
  end
  if max_bytes ~= nil then
    assert(type(max_bytes) == "number" and max_bytes > 0 and max_bytes == math.floor(max_bytes), "PTY read budget must be a positive integer")
  end
  local remaining = max_bytes or math.huge
  local chunks = {}
  local bytes_read = 0
  local read_calls = 0
  while remaining > 0 do
    local requested = math.min(8192, remaining)
    local amount = tonumber(ffi.C.read(self.fd, self.read_buffer, requested))
    if amount > 0 then
      local chunk = ffi.string(self.read_buffer, amount)
      chunks[#chunks + 1] = chunk
      self.bytes_read = self.bytes_read + amount
      bytes_read = bytes_read + amount
      read_calls = read_calls + 1
      remaining = remaining - amount
    elseif amount == 0 then
      self.eof = true
      break
    else
      local error_code = ffi.errno()
      if error_code == constants.eagain then
        break
      end
      if error_code == constants.eintr then
        -- Retry the interrupted read without publishing a partial result.
      elseif error_code == constants.eio then
        self.eof = true
        break
      else
        error(string.format("PTY read failed: errno %d", error_code))
      end
    end
  end
  self.last_read_bytes = bytes_read
  self.last_read_calls = read_calls
  return table.concat(chunks)
end

function Pty:enqueue(bytes)
  assert(type(bytes) == "string", "PTY input must be a byte string")
  if #bytes == 0 then
    return
  end
  if #self.pending - self.pending_offset + 1 + #bytes > 1024 * 1024 then
    error("PTY output queue exceeded 1 MiB")
  end
  if self.pending_offset > 1 then
    self.pending = self.pending:sub(self.pending_offset)
    self.pending_offset = 1
  end
  self.pending = self.pending .. bytes
end

function Pty:flush()
  if self.fd == nil or self.eof then
    self.pending = ""
    self.pending_offset = 1
    return false
  end
  while self.pending_offset <= #self.pending do
    local pointer = ffi.cast("const char *", self.pending) + self.pending_offset - 1
    local amount = tonumber(ffi.C.write(self.fd, pointer, #self.pending - self.pending_offset + 1))
    if amount > 0 then
      self.pending_offset = self.pending_offset + amount
      self.bytes_written = self.bytes_written + amount
    else
      local error_code = ffi.errno()
      if error_code == constants.eagain then
        break
      end
      if error_code == constants.eio then
        -- A PTY master reports EIO when its slave has closed. A terminal
        -- response cannot be delivered after that boundary, so do not turn a
        -- normally exiting child into an application failure.
        self.eof = true
        self.pending = ""
        self.pending_offset = 1
        return false
      end
      if error_code ~= constants.eintr then
        error(string.format("PTY write failed: errno %d", error_code))
      end
    end
  end
  if self.pending_offset > #self.pending then
    self.pending = ""
    self.pending_offset = 1
  end
  return true
end

function Pty:resize(columns, rows)
  assert(columns > 0 and rows > 0 and columns <= 65535 and rows <= 65535, "PTY dimensions must fit winsize")
  if self.fd == nil then
    return false
  end
  if native.kiwi_pty_resize(self.fd, columns, rows) ~= 0 then
    error(errno_message("TIOCSWINSZ"))
  end
  return true
end

function Pty:poll_exit()
  if self.exited or self.pid == nil then
    return self.exit_status
  end
  local status = ffi.new("int[1]")
  local result = ffi.C.waitpid(self.pid, status, constants.wnohang)
  if result == 0 then
    return nil
  end
  if result < 0 then
    local error_code = ffi.errno()
    if error_code == 10 then
      self.exited = true
      self.exit_status = { kind = "unknown" }
      return self.exit_status
    end
    error(string.format("waitpid failed: errno %d", error_code))
  end
  self.exited = true
  if bit.band(status[0], 0x7f) == 0 then
    self.exit_status = { kind = "exit", code = bit.band(bit.rshift(status[0], 8), 0xff) }
  else
    self.exit_status = { kind = "signal", signal = bit.band(status[0], 0x7f) }
  end
  return self.exit_status
end

local function signal_child_and_group(pty, signal)
  -- interactive shells can put themselves in a different foreground process
  -- group. Signal the group first for its jobs, then the direct child so an
  -- application shutdown cannot wait indefinitely for a moved shell.
  ffi.C.kill(-pty.pid, signal)
  ffi.C.kill(pty.pid, signal)
end

local function reap_for(pty, attempts, delay_microseconds)
  for _ = 1, attempts do
    if pty:poll_exit() then return true end
    ffi.C.usleep(delay_microseconds)
  end
  return false
end

function Pty:shutdown()
  if self.pid ~= nil and not self.exited then
    signal_child_and_group(self, constants.sighup)
    reap_for(self, 25, 10000)
    if not self.exited then
      signal_child_and_group(self, constants.sigterm)
      reap_for(self, 25, 10000)
    end
    if not self.exited then
      signal_child_and_group(self, constants.sigkill)
      reap_for(self, 25, 10000)
    end
    if not self.exited then
      -- SIGKILL was delivered to the direct child, but a pathological kernel
      -- reaping delay must not block the terminal's window teardown forever.
      self.exited = true
      self.exit_status = { kind = "unknown" }
    end
  end
  if self.fd ~= nil then
    ffi.C.close(self.fd)
    self.fd = nil
  end
end

return Pty
