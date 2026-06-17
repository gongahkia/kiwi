# kumeyuri.nvim

Neovim runtime plugin for previewing Mermaid files with kumeyuri.

`:KumeyuriPreview` opens a floating terminal and runs `kumeyuri play` against the current buffer file or an explicit file path.

## Install

Use this subdirectory as the runtime path:

```lua
{
  dir = "/path/to/kumeyuri/editors/nvim",
  opts = {
    command = "kumeyuri",
  },
}
```

For local repo development without installing the binary:

```lua
{
  dir = "/path/to/kumeyuri/editors/nvim",
  opts = {
    command = { "cargo", "run", "-q", "-p", "kumeyuri-cli", "--" },
  },
}
```

## Commands

- `:KumeyuriPreview` previews the current file.
- `:KumeyuriPreview path/to/file.mmd` previews a specific file.
- `:KumeyuriClose` closes the active preview.

## Options

```lua
require("kumeyuri").setup({
  command = "kumeyuri",
  width = 0.86,
  height = 0.82,
  border = "rounded",
  speed = nil,
  loop = false,
  close_on_exit = false,
  start_insert = true,
})
```

Run tests with:

```sh
nvim --headless -u NONE -n -c "luafile editors/nvim/tests/preview_spec.lua" -c qa
```
