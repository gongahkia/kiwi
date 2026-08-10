return {
  id = "shell-integration",
  source = "iTerm2 FinalTerm OSC 133 and OSC 7 current-directory conventions used by bash, zsh, and fish integrations",
  columns = 20,
  rows = 3,
  input = "\27]7;file://build.example/home/kiwi\27\\\27]133;A\7kiwi$ \27]133;B\7echo ok\27]133;C\7\r\nok\r\n\27]133;D;0\27\\",
  expected = {
    rows = { "kiwi$ echo ok       ", "ok                  ", "                    " },
    cursor = { column = 0, row = 2 },
    shell = {
      current_directory = "file://build.example/home/kiwi",
      events = { "cwd", "prompt", "command_start", "command_executed", "command_finished" },
    },
    command_regions = { state = "completed" },
  },
}
