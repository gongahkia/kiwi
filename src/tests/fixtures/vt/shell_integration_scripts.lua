return {
  id = "shell-integration-scripts",
  source = "integrations/v1 Bash, Zsh, and fish capture shape",
  columns = 16,
  rows = 1,
  input = "\27]7;file://host.example/tmp/kiwi%20work\7\27]133;A\7prompt\27]133;B\7\27]133;C\7run\27]133;D;0\7\27]7;file://host.example/tmp/kiwi%20work\7\27]133;A\7",
  expected = {
    rows = { "promptrun       " },
    cursor = { column = 9, row = 0 },
    shell = {
      current_directory = "file://host.example/tmp/kiwi%20work",
      events = { "cwd", "prompt", "command_start", "command_executed", "command_finished", "cwd", "prompt" },
    },
  },
}
