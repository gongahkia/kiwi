local Assert = require("tests.assert")
local ShellIntegration = require("kiwi.process.shell_integration")

local directory = "integrations/v1"

local function environment(values)
  return function(name) return values[name] end
end

return {
  shell_launcher_injects_bash_without_replacing_the_user_startup_path = function()
    local command, values, reason = ShellIntegration.prepare({ "/bin/bash" }, directory, environment({ HOME = "/home/test" }))
    Assert.equal(reason, nil)
    Assert.equal(command[1], "/bin/bash")
    Assert.equal(command[2], "--rcfile")
    Assert.equal(command[3], "integrations/v1/inject/kiwi.bashrc")
    Assert.equal(values.KIWI_SHELL_INTEGRATION, "1")
    Assert.equal(values.KIWI_SHELL_INTEGRATION_ORIGINAL_BASHRC, "/home/test/.bashrc")
  end,
  shell_launcher_injects_fish_after_its_normal_configuration = function()
    local command, values, reason = ShellIntegration.prepare({ "/usr/bin/fish" }, directory, environment({ HOME = "/home/test" }))
    Assert.equal(reason, nil)
    Assert.equal(command[2], "--init-command")
    Assert.equal(command[3], "source $KIWI_SHELL_INTEGRATION_SCRIPT")
    Assert.equal(values.KIWI_SHELL_INTEGRATION_SCRIPT, "integrations/v1/kiwi.fish")
  end,
  shell_launcher_stages_zsh_then_restores_its_original_configuration_location = function()
    local command, values, reason = ShellIntegration.prepare({ "/usr/bin/zsh" }, directory, environment({ HOME = "/home/test", ZDOTDIR = "/home/test/.zsh" }))
    Assert.equal(reason, nil)
    Assert.equal(command[1], "/usr/bin/zsh")
    Assert.equal(command[2], "-i")
    Assert.equal(values.ZDOTDIR, "integrations/v1/inject/zsh")
    Assert.equal(values.KIWI_SHELL_INTEGRATION_ORIGINAL_ZDOTDIR, "/home/test/.zsh")
  end,
  shell_launcher_injects_nushell_through_its_execute_interactive_startup = function()
    local command, values, reason = ShellIntegration.prepare({ "/usr/bin/nu" }, directory, environment({ HOME = "/home/test" }))
    Assert.equal(reason, nil)
    Assert.equal(command[1], "/usr/bin/nu")
    Assert.equal(command[2], "--execute")
    Assert.equal(command[3], "source \"integrations/v1/kiwi.nu\"")
    Assert.equal(command[4], "--interactive")
    Assert.equal(values.KIWI_SHELL_INTEGRATION_SCRIPT, "integrations/v1/kiwi.nu")
  end,
  shell_launcher_leaves_unsupported_or_resource_missing_shells_unchanged = function()
    local command, values, reason = ShellIntegration.prepare({ "/bin/sh" }, directory, environment({ HOME = "/home/test" }))
    Assert.equal(command[1], "/bin/sh")
    Assert.equal(next(values), nil)
    Assert.equal(reason, "unsupported-shell")
    local missing, missing_values, missing_reason = ShellIntegration.prepare({ "/bin/bash" }, "missing", environment({ HOME = "/home/test" }))
    Assert.equal(missing[1], "/bin/bash")
    Assert.equal(next(missing_values), nil)
    Assert.equal(missing_reason, "resources-unavailable")
  end,
}
