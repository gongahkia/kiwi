local Assert = require("tests.assert")
local root = os.getenv("KIWI_ROOT") or "."

local function shell_quote(value)
  return "'" .. value:gsub("'", "'\\''") .. "'"
end

local function temporary_directory()
  local handle = assert(io.popen("mktemp -d", "r"))
  local directory = assert(handle:read("*l"))
  assert(handle:close())
  return directory
end

local function execute(command)
  local pipe = assert(io.popen("(" .. command .. "); kiwi_exit=$?; printf '\\n__KIWI_EXIT_STATUS:%s' \"$kiwi_exit\"", "r"))
  local output = pipe:read("*a")
  pipe:close()
  local status = output:match("\n__KIWI_EXIT_STATUS:(%d+)$")
  assert(status ~= nil, "command did not report an exit status")
  return status == "0"
end

return {
  kiwi_ssh_uploads_the_compiled_terminfo_then_starts_a_kiwi_remote_shell = function()
    local temporary = temporary_directory()
    local log = temporary .. "/calls"
    local stub = root .. "/src/tests/fixtures/ssh-client-stub.sh"
    local setup = "ln -s " .. shell_quote(stub) .. " " .. shell_quote(temporary .. "/ssh") .. " && ln -s " .. shell_quote(stub) .. " " .. shell_quote(temporary .. "/scp")
    assert(execute(setup), "could not prepare SSH client stubs")

    local command = "PATH=" .. shell_quote(temporary) .. ":$PATH KIWI_SSH_TEST_LOG=" .. shell_quote(log) .. " KIWI_TERMINFO=" .. shell_quote(root .. "/src/tests/fixtures/terminfo") .. " " .. shell_quote(root .. "/script/kiwi-ssh") .. " -- user@example.test"
    local ok = execute(command)
    local handle = assert(io.open(log, "rb"))
    local calls = handle:read("*a")
    handle:close()
    os.remove(temporary .. "/ssh")
    os.remove(temporary .. "/scp")
    os.remove(log)
    assert(execute("rmdir " .. shell_quote(temporary)), "could not remove SSH test directory")

    Assert.truthy(ok)
    Assert.truthy(calls:find("ssh|user@example.test|mkdir -p \"$HOME/.cache/kiwi/terminfo/k\"", 1, true) ~= nil)
    Assert.truthy(calls:find("scp|" .. root .. "/src/tests/fixtures/terminfo/k/kiwi|user@example.test:.cache/kiwi/terminfo/k/kiwi", 1, true) ~= nil)
    Assert.truthy(calls:find("ssh|-tt|user@example.test|TERM=kiwi TERMINFO=\"$HOME/.cache/kiwi/terminfo\" exec \"${SHELL:-/bin/sh}\" -l", 1, true) ~= nil)
  end,
  kiwi_ssh_rejects_option_like_destinations_before_spawning_a_client = function()
    Assert.truthy(not execute("./script/kiwi-ssh -- -unsafe >/dev/null 2>&1"))
  end,
  kiwi_ssh_forwards_explicit_connection_options_to_setup_and_login = function()
    local temporary = temporary_directory()
    local log = temporary .. "/calls"
    local stub = root .. "/src/tests/fixtures/ssh-client-stub.sh"
    local setup = "ln -s " .. shell_quote(stub) .. " " .. shell_quote(temporary .. "/ssh") .. " && ln -s " .. shell_quote(stub) .. " " .. shell_quote(temporary .. "/scp")
    assert(execute(setup), "could not prepare SSH client stubs")

    local command = "PATH=" .. shell_quote(temporary) .. ":$PATH KIWI_SSH_TEST_LOG=" .. shell_quote(log) .. " KIWI_TERMINFO=" .. shell_quote(root .. "/src/tests/fixtures/terminfo") .. " " .. shell_quote(root .. "/script/kiwi-ssh") .. " --ssh-option -p --ssh-option 2201 -- user@example.test"
    local ok = execute(command)
    local handle = assert(io.open(log, "rb"))
    local calls = handle:read("*a")
    handle:close()
    os.remove(temporary .. "/ssh")
    os.remove(temporary .. "/scp")
    os.remove(log)
    assert(execute("rmdir " .. shell_quote(temporary)), "could not remove SSH test directory")

    Assert.truthy(ok)
    Assert.truthy(calls:find("ssh|-p|2201|user@example.test|mkdir -p \"$HOME/.cache/kiwi/terminfo/k\"", 1, true) ~= nil)
    Assert.truthy(calls:find("scp|-p|2201|" .. root .. "/src/tests/fixtures/terminfo/k/kiwi|user@example.test:.cache/kiwi/terminfo/k/kiwi", 1, true) ~= nil)
    Assert.truthy(calls:find("ssh|-p|2201|-tt|user@example.test|TERM=kiwi TERMINFO=\"$HOME/.cache/kiwi/terminfo\" exec \"${SHELL:-/bin/sh}\" -l", 1, true) ~= nil)
  end,
  kiwi_ssh_probe_verifies_the_uploaded_private_terminfo_entry = function()
    local temporary = temporary_directory()
    local log = temporary .. "/calls"
    local stub = root .. "/src/tests/fixtures/ssh-client-stub.sh"
    local setup = "ln -s " .. shell_quote(stub) .. " " .. shell_quote(temporary .. "/ssh") .. " && ln -s " .. shell_quote(stub) .. " " .. shell_quote(temporary .. "/scp")
    assert(execute(setup), "could not prepare SSH client stubs")

    local command = "PATH=" .. shell_quote(temporary) .. ":$PATH KIWI_SSH_TEST_LOG=" .. shell_quote(log) .. " KIWI_TERMINFO=" .. shell_quote(root .. "/src/tests/fixtures/terminfo") .. " " .. shell_quote(root .. "/script/kiwi-ssh") .. " --probe -- user@example.test"
    local ok = execute(command)
    local handle = assert(io.open(log, "rb"))
    local calls = handle:read("*a")
    handle:close()
    os.remove(temporary .. "/ssh")
    os.remove(temporary .. "/scp")
    os.remove(log)
    assert(execute("rmdir " .. shell_quote(temporary)), "could not remove SSH test directory")

    Assert.truthy(ok)
    Assert.truthy(calls:find("ssh|-tt|user@example.test|TERM=kiwi TERMINFO=\"$HOME/.cache/kiwi/terminfo\"; export TERM TERMINFO; infocmp kiwi >/dev/null && [ \"$(tput colors)\" = 16 ] && printf \"%s\\n\" \"kiwi-ssh probe: terminfo=kiwi colors=16\"", 1, true) ~= nil)
  end,
  kiwi_ssh_rejects_a_probe_without_the_private_terminfo_setup = function()
    Assert.truthy(not execute("./script/kiwi-ssh --no-terminfo --probe -- user@example.test >/dev/null 2>&1"))
  end,
}
