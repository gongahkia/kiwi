local Assert = require("tests.assert")
local Parser = require("kiwi.terminal.parser")
local State = require("kiwi.terminal.state")

local scripts = {
  bash = "TERM=kiwi KIWI_SHELL_INTEGRATION=1 HOSTNAME=host.example bash --noprofile --norc -ic 'source integrations/v1/kiwi.bash; PWD=\"/tmp/kiwi work\"; __kiwi_bash_prompt; printf prompt; __kiwi_bash_marker B; __kiwi_bash_marker C; printf run; __kiwi_bash_prompt; case $PS0 in *$'\"'\"'\\e]133;B\\a\\e]133;C\\a'\"'\"'*) ;; *) exit 1;; esac'",
  zsh = "TERM=kiwi KIWI_SHELL_INTEGRATION=1 HOSTNAME=host.example zsh -dfic 'source integrations/v1/kiwi.zsh; PWD=\"/tmp/kiwi work\"; __kiwi_zsh_precmd; printf prompt; __kiwi_zsh_preexec; printf run; __kiwi_zsh_precmd'",
  fish = "TERM=kiwi KIWI_SHELL_INTEGRATION=1 HOSTNAME=host.example fish --no-config -ic 'source integrations/v1/kiwi.fish; cd /tmp; emit fish_prompt; printf prompt; emit fish_preexec; printf run; emit fish_postexec; emit fish_prompt'",
}

local disabled = {
  "TERM=xterm KIWI_SHELL_INTEGRATION=1 bash --noprofile --norc -ic 'source integrations/v1/kiwi.bash; true'",
  "TERM=xterm KIWI_SHELL_INTEGRATION=1 zsh -dfic 'source integrations/v1/kiwi.zsh; true'",
  "TERM=xterm KIWI_SHELL_INTEGRATION=1 fish --no-config -ic 'source integrations/v1/kiwi.fish; true'",
}

local function capture(command)
  local pipe = assert(io.popen(command .. " 2>/dev/null", "r"))
  local output = pipe:read("*a")
  assert(pipe:close(), "shell integration command failed")
  return output
end

local function assert_capture(output, expected_path)
  Assert.truthy(output:find("\27]7;file://host.example" .. expected_path .. "\7", 1, true) ~= nil)
  local state = State.new(32, 2)
  Parser.new(state):feed(output)
  local shell = state.shell:view()
  Assert.equal(shell.current_directory.uri, "file://host.example" .. expected_path)
  Assert.equal(#shell.events, 7)
  Assert.equal(shell.events[2].kind, "prompt")
  Assert.equal(shell.events[3].kind, "command_start")
  Assert.equal(shell.events[4].kind, "command_executed")
  Assert.equal(shell.events[5].exit_status, 0)
  local regions = state.command_regions:view()
  Assert.equal(regions.regions[1].state, "completed")
  Assert.equal(regions.regions[2].state, "prompt")
end

return {
  shell_integration_scripts_emit_the_documented_bounded_event_shape = function()
    assert_capture(capture(scripts.bash), "/tmp/kiwi%20work")
    assert_capture(capture(scripts.zsh), "/tmp/kiwi%20work")
    assert_capture(capture(scripts.fish), "/tmp")
  end,

  shell_integration_scripts_are_silent_outside_kiwi = function()
    for _, command in ipairs(disabled) do Assert.equal(capture(command), "") end
  end,
}
