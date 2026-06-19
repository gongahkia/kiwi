# Neovim

`editors/nvim` provides `:KumeyuriPreview`, which opens a floating terminal and
runs `kumeyuri play`.

```lua
{
  dir = "/path/to/kumeyuri/editors/nvim",
  opts = {
    command = "kumeyuri",
  },
}
```

Commands:

| Command | Purpose |
| --- | --- |
| `:KumeyuriPreview` | Preview the current file |
| `:KumeyuriPreview path/to/file.mmd` | Preview a specific file |
| `:KumeyuriClose` | Close the active preview |
