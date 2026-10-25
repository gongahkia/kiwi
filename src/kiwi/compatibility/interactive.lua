-- Real programs driven through Kiwi's PTY, parser/state and input encoders.
-- No window is opened: native input delivery and rendering are separate gates.
local ffi = require("ffi")
local Pty = require("kiwi.process.pty")
local Terminal = require("kiwi.session.terminal")
local Keyboard = require("kiwi.input.keyboard")
local Clipboard = require("kiwi.input.clipboard")
local Utf8 = require("kiwi.terminal.utf8")
local Replay = require("kiwi.terminal.replay")
local Snapshot = require("kiwi.terminal.snapshot")
local Json = require("kiwi.bench.json")
local Metrics = require("kiwi.bench.process_metrics")
local glfw = require("kiwi.ffi.glfw").constants
ffi.cdef[[int tcgetpgrp(int fd);]]

local work = assert(os.getenv("KIWI_INTERACTIVE_WORK"), "run script/test-applications")
local artifacts = assert(os.getenv("KIWI_INTERACTIVE_ARTIFACTS"))
local root = assert(os.getenv("KIWI_ROOT"))
local Session = {}
Session.__index = Session

local function write(path, bytes)
  local file = assert(io.open(path, "wb"))
  assert(file:write(bytes)); assert(file:close())
end

local function read(path)
  local file = io.open(path, "rb")
  if not file then return nil end
  local bytes = file:read("*a"); file:close(); return bytes
end

local function quote(value) return "'" .. value:gsub("'", "'\\''") .. "'" end

local function first_line(command)
  local pipe = assert(io.popen("(" .. command .. ") 2>/dev/null", "r"))
  local line = pipe:read("*l")
  pipe:close()
  return (line or "unavailable"):sub(1, 256)
end

local function tmux_config()
  local path = work .. "/tmux.conf"
  write(path, 'set -g default-shell /bin/sh\nset -g default-command "/bin/sh -i"\nset -g status-left ""\nset -g status-right ""\n')
  return path
end

function Session.new(name, command)
  local terminal = Terminal.new({ columns = 80, rows = 24 })
  -- Apply every recorded resize, including initialization. Even a same-size
  -- resize currently allocates row IDs used by shell metadata snapshots.
  terminal:resize(80, 24)
  terminal:set_cell_metrics(8, 16)
  local negative_probes = { dcs = 0, csi = 0 }
  local state = Terminal.state(terminal)
  local record_unknown = state.record_unknown
  state.record_unknown = function(self, family, detail)
    if name == "vim" and family == "dcs" and detail == "unsupported"
      and table.concat(Terminal.parser(terminal).string_chunks) == "zz" then
      negative_probes.dcs = negative_probes.dcs + 1
    elseif name == "vim" and family == "csi" and type(detail) == "table"
      and detail.private == "" and detail.intermediates == "%" and detail.final == "m"
      and not detail.colon and #detail.parameters == 1 and detail.parameters[1] == 0 then
      negative_probes.csi = negative_probes.csi + 1
    end
    record_unknown(self, family, detail)
  end
  local recorder = Replay.Recorder.new(artifacts .. "/" .. name .. ".jsonl")
  recorder:resize(80, 24, 8, 16)
  local environment = require("kiwi.process.environment").terminal(root .. "/.build/terminfo")
  for name, value in pairs({
    HOME = work, ZDOTDIR = work, XDG_CONFIG_HOME = work, XDG_DATA_HOME = work,
    XDG_STATE_HOME = work, XDG_CACHE_HOME = work, HISTFILE = "/dev/null",
    INPUTRC = "/dev/null", ENV = false, BASH_ENV = false, VIMINIT = false, EXINIT = false,
    TMUX = false, TMUX_PANE = false, PS1 = "KIWI> ", PROMPT = "KIWI> ", PS2 = "MORE> ",
    LC_ALL = ffi.os == "OSX" and "en_US.UTF-8" or "C.UTF-8", BASH_SILENCE_DEPRECATION_WARNING = "1", LESS = "", LESSOPEN = false, LESSCLOSE = false,
    LESSHISTFILE = "-", LESSCHARSET = "utf-8", NVIM = false, NVIM_LISTEN_ADDRESS = false,
  }) do environment[name] = value end
  local ok, pty = pcall(Pty.spawn, command, 80, 24, environment, { cwd = work })
  if not ok then recorder:close(); error(pty) end
  return setmetatable({ name = name, terminal = terminal, state = Terminal.state(terminal),
    pty = pty, recorder = recorder, checkpoints = {}, output_bytes = 0, input_bytes = 0,
    response_bytes = 0, resize_count = 0, negative_probes = negative_probes, started = Metrics.monotonic_seconds() }, Session)
end

function Session:screen()
  local lines = {}
  for row = 0, self.state.rows - 1 do
    local cells = {}
    for column = 0, self.state.columns - 1 do
      local cell = self.state:get(column, row)
      if not cell.continuation then cells[#cells + 1] = cell.glyph end
    end
    lines[#lines + 1] = table.concat(cells):gsub(" +$", "")
  end
  return table.concat(lines, "\n")
end

function Session:pump()
  local output = self.pty:read_available(16384)
  if #output > 0 then
    self.output_bytes = self.output_bytes + #output
    assert(self.output_bytes <= 2 * 1024 * 1024, "application exceeded bounded capture size")
    self.recorder:output(output)
    self.terminal:write(output)
  end
  local responses = table.concat(self.terminal:pop_responses())
  if #responses > 0 then
    self.response_bytes = self.response_bytes + #responses
    self.recorder:input(responses)
    self.pty:enqueue(responses)
  end
  self.pty:flush()
  self.exit_status = self.pty:poll_exit()
end

function Session:wait(label, predicate)
  local deadline = Metrics.monotonic_seconds() + 8
  repeat
    self:pump()
    if predicate() then
      self.checkpoints[#self.checkpoints + 1] = { label = label, screen = self:screen(),
        columns = self.state.columns, rows = self.state.rows,
        alternate = self.state.active_screen == self.state.alternate, bracketed_paste = self.state.modes.bracketed_paste }
      return
    end
    assert(not (self.exit_status and self.pty.eof), "child exited before " .. label)
    ffi.C.usleep(2000)
  until Metrics.monotonic_seconds() >= deadline
  error("timed out waiting for " .. label .. "\n" .. self:screen())
end

function Session:expect(text)
  self:wait(text, function() return self:screen():find(text, 1, true) ~= nil end)
end

function Session:prompt()
  self:wait("shell prompt ready", function()
    local cells = {}
    for column = 0, self.state.columns - 1 do cells[#cells + 1] = self.state:get(column, self.state.cursor.row).glyph end
    return table.concat(cells):gsub(" +$", "") == "KIWI>"
  end)
end

function Session:send(bytes)
  assert(type(bytes) == "string" and #bytes <= 65536, "input must be bounded encoded text")
  self.recorder:input(bytes)
  self.input_bytes = self.input_bytes + #bytes
  self.pty:enqueue(bytes); self.pty:flush()
end

function Session:text(text)
  local codepoints = {}
  local decoder = Utf8.Decoder.new(function(codepoint, _, replaced)
    assert(not replaced, "invalid test UTF-8"); codepoints[#codepoints + 1] = codepoint
  end)
  for index = 1, #text do decoder:feed_byte(text:byte(index)) end
  decoder:finish()
  self:send(assert(Keyboard.text_sequence(codepoints, self.state.modes)))
end

function Session:key(key, modifiers)
  local encoded = Keyboard.key(key, glfw.press, modifiers or 0, self.state.modes, glfw)
  self:send(assert(encoded and encoded.bytes, "test key did not encode to terminal input"))
end

function Session:paste(text)
  local clipboard = Clipboard.new({ clipboard_read = function() return text end, clipboard_write = function() return true end })
  self:send(assert(clipboard:paste(self.state)))
end

function Session:command(command)
  self:text(command); self:key(glfw.key_enter)
end

function Session:resize(columns, rows)
  self.recorder:resize(columns, rows, 8, 16)
  self.terminal:resize(columns, rows); self.pty:resize(columns, rows)
  self.resize_count = self.resize_count + 1
end

function Session:exited()
  self:wait("clean exit", function() return self.exit_status and self.pty.eof end)
  assert(self.exit_status.kind == "exit" and self.exit_status.code == 0, "application exited unsuccessfully")
  self.terminal:finish()
  assert(self.state.active_screen == self.state.primary, "application left alternate screen active")
end

function Session:close()
  write(artifacts .. "/" .. self.name .. "-checkpoints.json", Json.encode(self.checkpoints) .. "\n")
  write(artifacts .. "/" .. self.name .. "-screen.txt", self:screen() .. "\n")
  self.recorder:close()
  self.pty:shutdown()
end

local function editor(session, name, multiplexed)
  session:expect("KIWI-READY")
  assert(session.state.active_screen == session.state.alternate, "editor did not enter alternate screen")
  session:text("i")
  session:expect("INSERT")
  session:paste("alpha 界 é\nsecond line")
  session:expect("second line")
  session:key(glfw.key_escape)
  session:command(":write " .. name .. ".txt")
  session:wait("saved Unicode paste", function() return read(work .. "/" .. name .. ".txt") == "alpha 界 é\nsecond line\n" end)
  session:command(":autocmd VimResized * call writefile([string(&columns), string(&lines)], '" .. name .. "-size.txt')")
  session:command(":echo join(['KIWI', 'SIZE', 'ARMED'], '-')")
  session:expect("KIWI-SIZE-ARMED")
  session:resize(53, multiplexed and 18 or 17)
  session:wait("editor observed SIGWINCH", function() return read(work .. "/" .. name .. "-size.txt") == "53\n17\n" end)
  session:command(":normal! gg0")
  session:text("i")
  session:expect("INSERT")
  session:key(glfw.key_right)
  session:text("X")
  session:key(glfw.key_backspace)
  session:text("Z")
  session:key(glfw.key_escape)
  session:command(":wq")
  session:exited()
  local saved = read(work .. "/" .. name .. ".txt")
  write(artifacts .. "/" .. name .. "-saved.txt", saved or "missing")
  assert(saved == "aZlpha 界 é\nsecond line\n", "editor saved unexpected text: " .. tostring(saved))
end

local function shell(session, remote)
  session:prompt()
  session:text("printf 'KIWI-EDIT-%s\\n' abXd")
  session:key(glfw.key_left); session:key(glfw.key_backspace); session:text("c")
  session:key(glfw.key_enter)
  session:expect("KIWI-EDIT-abcd")
  session:prompt()
  session:resize(61, 19)
  session:command("stty size")
  session:expect("19 61")
  session:prompt()
  session:paste("printf 'KIWI-PASTE-%s\\n' '界 é'")
  session:key(glfw.key_enter)
  session:expect("KIWI-PASTE-界 é")
  session:prompt()
  if remote then
    session:command("sh -c 'printf ready > ssh-job-ready; exec sleep 30'")
    session:wait("remote foreground job started", function() return read(work .. "/ssh-job-ready") == "ready" end)
  else
    session:command("/bin/sleep 30")
    session:wait("foreground job started", function()
      local group = ffi.C.tcgetpgrp(session.pty.fd)
      return group > 0 and group ~= session.pty.pid
    end)
  end
  session:key(string.byte("C"), glfw.mod_control)
  if not remote then
    session:wait("shell regained foreground", function() return ffi.C.tcgetpgrp(session.pty.fd) == session.pty.pid end)
  end
  session:prompt()
  session:command("printf 'KIWI-INTERRUPT-%s\\n' OK")
  session:expect("KIWI-INTERRUPT-OK")
  session:command("exit")
  session:exited()
end

local vim_command = os.getenv("KIWI_INTERACTIVE_VIM") or "vim"
local vim_version = first_line(quote(vim_command) .. " --version")
if not os.getenv("KIWI_INTERACTIVE_VIM") and not vim_version:match("^VIM ") and ffi.os == "Linux" then
  -- Debian alternatives may make `vim` invoke Neovim after installation.
  -- Qualify both editors, even when that alternative is the system default.
  local basic_version = first_line("vim.basic --version")
  if basic_version:match("^VIM ") then vim_command, vim_version = "vim.basic", basic_version end
end
local revision = first_line("git rev-parse --short HEAD")
local git_status = first_line("git status --porcelain --untracked-files=no && printf 'KIWI_GIT_CLEAN\\n'")
local source_state = git_status == "KIWI_GIT_CLEAN" and "clean" or (git_status == "unavailable" and "unavailable" or "dirty")
if revision == "unavailable" then revision = require("kiwi.build").info().revision end
local report = { schema_version = 1, kind = "kiwi-interactive-applications", checks = {},
  scope = "real PTY, parser/state, keyboard/paste encoding, resize, saved-file assertions and chunk-invariant replay; no native UI or GPU",
  platform = ffi.os .. "-" .. ffi.arch, kernel = first_line("uname -sr"),
  revision = revision, timestamp_utc = os.date("!%Y-%m-%dT%H:%M:%SZ"),
  source_state = source_state,
  network = os.getenv("KIWI_INTERACTIVE_SSH") and "loopback TCP; temporary key-authenticated OpenSSH server" or "not used",
  versions = { bash = first_line("bash --version"), zsh = first_line("zsh --version"),
    vim = vim_version, nvim = first_line("nvim --version"),
    tmux = first_line("tmux -V"), less = first_line("less --version"), top = "platform system top",
    ssh = os.getenv("KIWI_INTERACTIVE_SSH_VERSION") or "not exercised" } }
report.versions.fish = first_line("fish --version")
report.versions.nu = first_line("nu --version")
local failed = false
local function run(name, command, body, cleanup)
  local session
  local entry = { name = name }
  local ok, message = xpcall(function()
    if name == "vim" then assert(vim_version:match("^VIM "), "Vim case requires Vim, not an alternative editor; set KIWI_INTERACTIVE_VIM") end
    session = Session.new(name, command)
    body(session)
    local stats = Terminal.parser(session.terminal).stats
    assert(session.negative_probes.dcs <= 1 and session.negative_probes.csi <= 1, "unexpected repeated negative probes")
    assert(stats.errors == 0 and stats.ignored == session.negative_probes.dcs, "parser rejected application controls")
    for kind, count in pairs(session.state.stats.unknown) do
      assert(count == (session.negative_probes[kind] or 0), "unsupported application " .. kind .. " controls: " .. count)
    end
    entry.negative_probes = session.negative_probes
    entry.parser = stats
    entry.unknown = session.state.stats.unknown
    session:close()
    local replayed, replay_stats = Replay.verify_chunk_invariance(artifacts .. "/" .. name .. ".jsonl")
    local replay_snapshot, live_snapshot = Snapshot.encode(replayed), Snapshot.encode(session.state)
    if replay_snapshot ~= live_snapshot then
      write(artifacts .. "/" .. name .. "-live.json", live_snapshot)
      write(artifacts .. "/" .. name .. "-replay.json", replay_snapshot)
      error("live application and replay differ")
    end
    assert(replay_stats.errors == 0 and replay_stats.ignored == session.negative_probes.dcs)
    entry.output_bytes, entry.input_bytes, entry.response_bytes = session.output_bytes, session.input_bytes, session.response_bytes
    entry.resizes, entry.checkpoints = session.resize_count, #session.checkpoints
    entry.elapsed_ms = (Metrics.monotonic_seconds() - session.started) * 1000
    entry.chunking = "whole+one-byte+8-random"
  end, debug.traceback)
  if session then pcall(session.close, session) end
  if cleanup then cleanup() end
  entry.status = ok and "passed" or "failed"
  if not ok then failed = true; entry.detail = message; io.stderr:write(message, "\n") end
  report.checks[#report.checks + 1] = entry
  io.stdout:write(entry.status:upper(), " ", name, "\n"); io.stdout:flush()
  write(artifacts .. "/report.json", Json.encode(report) .. "\n")
end

write(artifacts .. "/report.json", Json.encode(report) .. "\n")
local applications = os.getenv("KIWI_INTERACTIVE_APPS") or "bash,zsh,fish,vim,nvim,tmux,tmux-nvim,less,top"
assert(applications ~= "" and not applications:find("^,") and not applications:find(",$") and not applications:find(",,"), "application list must not contain empty entries")
local supported = { bash = true, zsh = true, vim = true, nvim = true, tmux = true, ["tmux-nvim"] = true, less = true, top = true,
  fish = true, nu = true, ["ssh-shell"] = true, ["ssh-nvim"] = true, ["ssh-tmux-nvim"] = true, ["ssh-hangup"] = true }
for name in applications:gmatch("[^,]+") do assert(supported[name], "unknown application: " .. name) end
for name in applications:gmatch("[^,]+") do
  if name == "bash" then run(name, { "bash", "--noprofile", "--norc", "-i" }, shell)
  elseif name == "zsh" then run(name, { "zsh", "-d", "-f", "-i" }, shell)
  elseif name == "fish" then
    run(name, { "fish", "--no-config", "--interactive", "--init-command",
      "function fish_prompt; printf 'KIWI> '; end; function fish_right_prompt; end; set -g fish_greeting" }, shell)
  elseif name == "nu" then
    run(name, { "nu", "--no-config-file", "--interactive", "--execute",
      "$env.config.show_banner = false; $env.PROMPT_COMMAND = {|| 'KIWI> '}; $env.PROMPT_COMMAND_RIGHT = {|| ''}; $env.PROMPT_INDICATOR = ''" }, shell)
  elseif name:sub(1, 4) == "ssh-" then
    local client = assert(os.getenv("KIWI_INTERACTIVE_SSH"), "run script/test-ssh-applications for SSH cases")
    run(name, { client, name:sub(5) }, function(s)
      if name == "ssh-shell" then shell(s, true)
      elseif name == "ssh-hangup" then
        s:expect("KIWI-REMOTE-READY")
        s.pty:shutdown()
        local deadline = Metrics.monotonic_seconds() + 8
        while read(work .. "/ssh-closed.txt") ~= "remote-hangup\n" and Metrics.monotonic_seconds() < deadline do ffi.C.usleep(2000) end
        assert(read(work .. "/ssh-closed.txt") == "remote-hangup\n", "closing the local PTY did not hang up the remote application")
        s.terminal:finish()
      else editor(s, name, name == "ssh-tmux-nvim") end
    end)
  elseif name == "vim" or name == "nvim" then
    run(name, { name == "vim" and vim_command or name, "-N", "-u", "NONE", "-i", "NONE", "-n", "--noplugin", "-c", "set noswapfile showmode", "-c", "echo 'KIWI-READY'" }, function(s) editor(s, name) end)
  elseif name == "tmux-nvim" then
    local socket = work .. "/nested.sock"
    run(name, { "tmux", "-S", socket, "-f", tmux_config(), "new-session", "-s", "kiwi-editor",
      "nvim", "-N", "-u", "NONE", "-i", "NONE", "-n", "--noplugin", "-c", "set noswapfile showmode", "-c", "echo 'KIWI-READY'" },
      function(s) editor(s, name, true) end,
      function() os.execute("tmux -S " .. quote(socket) .. " kill-server >/dev/null 2>&1") end)
  elseif name == "less" then
    local lines = {}
    for line = 1, 120 do lines[#lines + 1] = string.format("KIWI-LINE-%03d 界 é", line) end
    write(work .. "/pager.txt", table.concat(lines, "\n") .. "\n")
    run(name, { "less", "-R", "-S", "pager.txt" }, function(s)
      s:expect("KIWI-LINE-001")
      assert(s.state.active_screen == s.state.alternate)
      s:command("/KIWI-LINE-077")
      s:expect("KIWI-LINE-077")
      s:resize(47, 13)
      -- less can discard pending input while handling SIGWINCH. Wait for its
      -- prompt on the new last row before sending the next navigation key.
      s:wait("pager resized prompt", function()
        return s.state.cursor.row == 12 and s.state:get(0, 12).glyph == ":"
      end)
      s:text("g"); s:expect("KIWI-LINE-001")
      s:key(glfw.key_page_down)
      s:wait("pager advanced", function() return s:screen():find("KIWI-LINE-023", 1, true) and not s:screen():find("KIWI-LINE-001", 1, true) end)
      s:text("q"); s:exited()
    end)
  elseif name == "tmux" then
    local socket = work .. "/tmux.sock"
    run(name, { "tmux", "-S", socket, "-f", tmux_config(), "new-session", "-s", "kiwi", "/bin/sh", "-i" }, function(s)
      s:expect("KIWI>")
      s:command("printf 'KIWI-PANE-%s\\n' ONE")
      s:expect("KIWI-PANE-ONE")
      s:key(string.byte("B"), glfw.mod_control); s:text("%")
      s:command("printf 'KIWI-PANE-%s\\n' TWO")
      s:expect("KIWI-PANE-TWO")
      assert(s:screen():find("KIWI-PANE-ONE", 1, true), "tmux split lost the first pane")
      s:resize(100, 30)
      s:command("while :; do set -- $(stty size); [ \"$1\" = 29 ] && [ \"$2\" -gt 40 ] && break; sleep .02; done; printf 'KIWI-SIZE-%s\\n' \"$*\"")
      s:expect("KIWI-SIZE-29 ")
      s:key(string.byte("B"), glfw.mod_control); s:text("z")
      s:wait("zoomed second pane", function() return not s:screen():find("│", 1, true) and s:screen():find("KIWI-PANE-TWO", 1, true) end)
      s:key(string.byte("B"), glfw.mod_control); s:text("z")
      s:wait("restored split", function() return s:screen():find("│", 1, true) and s:screen():find("KIWI-PANE-ONE", 1, true) end)
      s:command("exit")
      s:wait("closed second pane", function() return not s:screen():find("│", 1, true) and s:screen():find("KIWI-PANE-ONE", 1, true) end)
      s:command("printf 'KIWI-RESTORED-%s\\n' OK")
      s:expect("KIWI-RESTORED-OK")
      s:command("exit"); s:exited()
    end, function() os.execute("tmux -S " .. quote(socket) .. " kill-server >/dev/null 2>&1") end)
  elseif name == "top" then
    local command = ffi.os == "OSX" and "exec top -pid $$ -s 1" or "exec top -p $$ -d 0.2"
    run(name, { "/bin/sh", "-c", command }, function(s)
      s:expect("PID")
      s:resize(100, 30)
      s:expect("top")
      s:text("q"); s:exited()
    end)
  else error("unknown application: " .. name) end
end
if failed then os.exit(1) end
io.stdout:write("Interactive application checks passed; controlled recordings: ", artifacts, "\n")
