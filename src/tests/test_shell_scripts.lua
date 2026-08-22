local Assert = require("tests.assert")
local Parser = require("kiwi.terminal.parser")
local State = require("kiwi.terminal.state")

local function shell_available(name)
  local pipe = assert(io.popen("command -v " .. name .. " 2>/dev/null", "r"))
  local path = pipe:read("*a")
  pipe:close()
  return #path > 0
end

local has_nushell = shell_available("nu")

local scripts = {
  bash = "TERM=xterm-kiwi KIWI_SHELL_INTEGRATION=1 HOSTNAME=host.example bash --noprofile --norc -ic 'source integrations/v1/kiwi.bash; PWD=\"/tmp/kiwi work\"; __kiwi_bash_prompt; printf prompt; __kiwi_bash_marker B; __kiwi_bash_marker C; printf run; __kiwi_bash_prompt; [[ -n $PS0 ]]'",
  zsh = "TERM=xterm-kiwi KIWI_SHELL_INTEGRATION=1 HOSTNAME=host.example zsh -dfic 'source integrations/v1/kiwi.zsh; PWD=\"/tmp/kiwi work\"; __kiwi_zsh_precmd; printf prompt; __kiwi_zsh_preexec; printf run; __kiwi_zsh_precmd'",
  fish = "TERM=xterm-kiwi KIWI_SHELL_INTEGRATION=1 HOSTNAME=host.example fish --no-config -ic 'source integrations/v1/kiwi.fish; cd /tmp; emit fish_prompt; printf prompt; emit fish_preexec; printf run; emit fish_postexec; emit fish_prompt'",
}
if has_nushell then
  scripts.nu = "TERM=xterm-kiwi KIWI_SHELL_INTEGRATION=1 HOSTNAME=host.example nu --no-config-file -i -c 'source integrations/v1/kiwi.nu; cd /tmp; __kiwi_nu_prompt; print -n prompt; __kiwi_nu_preexec; print -n run; $env.LAST_EXIT_CODE = 0; __kiwi_nu_prompt'"
end

local disabled = {
  "TERM=xterm KIWI_SHELL_INTEGRATION=1 bash --noprofile --norc -ic 'source integrations/v1/kiwi.bash; true'",
  "TERM=xterm KIWI_SHELL_INTEGRATION=1 zsh -dfic 'source integrations/v1/kiwi.zsh; true'",
  "TERM=xterm KIWI_SHELL_INTEGRATION=1 fish --no-config -ic 'source integrations/v1/kiwi.fish; true'",
}
if has_nushell then disabled[#disabled + 1] = "TERM=xterm KIWI_SHELL_INTEGRATION=1 nu --no-config-file -i -c 'source integrations/v1/kiwi.nu'" end

local uninstall = {
  "TERM=xterm-kiwi KIWI_SHELL_INTEGRATION=1 bash --noprofile --norc -ic 'source integrations/v1/kiwi.bash; kiwi_shell_integration_uninstall; [[ -z ${PROMPT_COMMAND-} && -z ${PS0-} ]]'",
  "TERM=xterm-kiwi KIWI_SHELL_INTEGRATION=1 zsh -dfic 'source integrations/v1/kiwi.zsh; kiwi_shell_integration_uninstall; (( ! $+functions[__kiwi_zsh_precmd] ))'",
  "TERM=xterm-kiwi KIWI_SHELL_INTEGRATION=1 fish --no-config -ic 'source integrations/v1/kiwi.fish; kiwi_shell_integration_uninstall; not functions -q __kiwi_fish_prompt'",
}
if has_nushell then uninstall[#uninstall + 1] = "TERM=xterm-kiwi KIWI_SHELL_INTEGRATION=1 nu --no-config-file -i -c 'source integrations/v1/kiwi.nu; kiwi_shell_integration_uninstall; if ($env.__kiwi_nu_active? | default false) { error \"integration still active\" }'" end

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
    if has_nushell then assert_capture(capture(scripts.nu), "/tmp") end
  end,

  shell_integration_scripts_are_silent_outside_kiwi = function()
    for _, command in ipairs(disabled) do Assert.equal(capture(command), "") end
  end,

  shell_integration_scripts_are_reversible_and_preserve_bash_prompt_status = function()
    for _, command in ipairs(uninstall) do capture(command) end
    local output = capture("TERM=xterm-kiwi KIWI_SHELL_INTEGRATION=1 bash --noprofile --norc -ic 'PROMPT_COMMAND=\"printf original:\\$?\"; source integrations/v1/kiwi.bash; false; eval \"$PROMPT_COMMAND\"'")
    Assert.truthy(output:find("original:1", 1, true) ~= nil)
  end,

  shell_integration_launchers_source_the_supported_initial_shells = function()
    local bash = capture("TERM=xterm-kiwi KIWI_SHELL_INTEGRATION=1 KIWI_SHELL_INTEGRATION_SCRIPT=integrations/v1/kiwi.bash KIWI_SHELL_INTEGRATION_ORIGINAL_BASHRC=/dev/null bash --noprofile --rcfile integrations/v1/inject/kiwi.bashrc -ic '__kiwi_bash_prompt'")
    Assert.truthy(bash:find("\27]133;A\7", 1, true) ~= nil)

    local zsh = capture("TERM=xterm-kiwi KIWI_SHELL_INTEGRATION=1 KIWI_SHELL_INTEGRATION_SCRIPT=integrations/v1/kiwi.zsh KIWI_SHELL_INTEGRATION_ORIGINAL_ZDOTDIR=/dev/null KIWI_SHELL_INTEGRATION_INJECT_DIR=integrations/v1/inject/zsh ZDOTDIR=integrations/v1/inject/zsh zsh -i -c '__kiwi_zsh_precmd'")
    Assert.truthy(zsh:find("\27]133;A\7", 1, true) ~= nil)

    local fish = capture("TERM=xterm-kiwi KIWI_SHELL_INTEGRATION=1 KIWI_SHELL_INTEGRATION_SCRIPT=integrations/v1/kiwi.fish fish --no-config --init-command 'source $KIWI_SHELL_INTEGRATION_SCRIPT' -ic 'emit fish_prompt'")
    Assert.truthy(fish:find("\27]133;A\7", 1, true) ~= nil)

    if has_nushell then
      local nu = capture("TERM=xterm-kiwi KIWI_SHELL_INTEGRATION=1 nu --no-config-file -i -c 'source integrations/v1/kiwi.nu; __kiwi_nu_prompt'")
      Assert.truthy(nu:find("\27]133;A\7", 1, true) ~= nil)
    end
  end,
}
