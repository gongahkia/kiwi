# @wat/lsp

stdio Language Server Protocol server for wat hovers.

Build:

```sh
pnpm --filter @wat/lsp build
```

Neovim command example:

```lua
vim.lsp.start({
  name = "wat",
  cmd = { "node", "/absolute/path/to/wat/apps/lsp/dist/index.js" },
  root_dir = vim.fn.getcwd(),
})
```

The server returns hover Markdown for acronym-like tokens found in the public seed corpus.
