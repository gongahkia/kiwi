local M = {}

local defaults = {
  command = "kumeyuri",
  width = 0.86,
  height = 0.82,
  border = "rounded",
  speed = nil,
  loop = false,
  close_on_exit = false,
  start_insert = true,
}

local config = vim.deepcopy(defaults)
local state = {
  buf = nil,
  win = nil,
  job = nil,
}

local function notify(message, level)
  vim.notify(message, level or vim.log.levels.INFO, { title = "kumeyuri.nvim" })
end

local function merged_config(opts)
  return vim.tbl_deep_extend("force", vim.deepcopy(config), opts or {})
end

local function append_command(argv, command)
  if type(command) == "table" then
    for _, part in ipairs(command) do
      table.insert(argv, tostring(part))
    end
    return
  end
  table.insert(argv, tostring(command))
end

local function command_name(command)
  if type(command) == "table" then
    return command[1]
  end
  return command
end

local function clamp(value, min, max)
  return math.max(min, math.min(max, value))
end

local function resolve_dimension(value, total, ratio, min_size, max_size)
  local resolved
  if type(value) == "number" and value > 0 and value < 1 then
    resolved = math.floor(total * value)
  elseif type(value) == "number" and value >= 1 then
    resolved = math.floor(value)
  else
    resolved = math.floor(total * ratio)
  end
  return clamp(resolved, math.min(min_size, max_size), max_size)
end

function M._build_argv(file, opts)
  local cfg = merged_config(opts)
  local argv = {}
  append_command(argv, cfg.command)
  table.insert(argv, "play")
  if cfg.speed ~= nil then
    table.insert(argv, "--speed")
    table.insert(argv, tostring(cfg.speed))
  end
  if cfg.loop then
    table.insert(argv, "--loop")
  end
  table.insert(argv, file)
  return argv
end

function M._resolve_dimensions(opts, columns, lines)
  local cfg = merged_config(opts)
  local max_width = math.max(1, columns - 4)
  local max_height = math.max(1, lines - 4)
  local width = resolve_dimension(cfg.width, columns, defaults.width, 20, max_width)
  local height = resolve_dimension(cfg.height, lines, defaults.height, 8, max_height)
  return {
    width = width,
    height = height,
    col = math.max(0, math.floor((columns - width) / 2)),
    row = math.max(0, math.floor((lines - height) / 2)),
  }
end

function M._resolve_file(file)
  local path = file
  if path == nil or path == "" then
    path = vim.api.nvim_buf_get_name(0)
  end
  if path == nil or path == "" then
    return nil, "no file to preview"
  end

  local absolute = vim.fn.fnamemodify(path, ":p")
  local uv = vim.uv or vim.loop
  local stat = uv.fs_stat(absolute)
  if not stat or stat.type ~= "file" then
    return nil, "file not found: " .. absolute
  end
  return absolute, nil
end

function M.close()
  if state.job then
    pcall(vim.fn.jobstop, state.job)
  end
  if state.win and vim.api.nvim_win_is_valid(state.win) then
    pcall(vim.api.nvim_win_close, state.win, true)
  end
  state.buf = nil
  state.win = nil
  state.job = nil
end

local function open_float(cfg)
  M.close()
  local screen_lines = math.max(1, vim.o.lines - vim.o.cmdheight)
  local geometry = M._resolve_dimensions(cfg, vim.o.columns, screen_lines)
  local buf = vim.api.nvim_create_buf(false, true)
  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    width = geometry.width,
    height = geometry.height,
    col = geometry.col,
    row = geometry.row,
    style = "minimal",
    border = cfg.border,
    title = " kumeyuri ",
    title_pos = "center",
  })

  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].buflisted = false
  vim.bo[buf].filetype = "kumeyuri-preview"
  vim.bo[buf].swapfile = false
  vim.wo[win].number = false
  vim.wo[win].relativenumber = false
  vim.wo[win].signcolumn = "no"

  return buf, win
end

function M.open(opts)
  local cfg = merged_config(opts)
  local file, err = M._resolve_file(cfg.file)
  if not file then
    notify("kumeyuri: " .. err, vim.log.levels.ERROR)
    return nil
  end

  local executable = command_name(cfg.command)
  if type(executable) ~= "string" or executable == "" or vim.fn.executable(executable) == 0 then
    notify("kumeyuri: executable not found: " .. tostring(executable), vim.log.levels.ERROR)
    return nil
  end

  if vim.bo.modified then
    notify("kumeyuri: preview uses the saved file on disk", vim.log.levels.WARN)
  end

  local buf, win = open_float(cfg)
  local argv = M._build_argv(file, cfg)
  local job = vim.fn.termopen(argv, {
    on_exit = function(job_id, code)
      vim.schedule(function()
        if state.job == job_id then
          state.job = nil
          if cfg.close_on_exit and code == 0 then
            M.close()
          end
        end
      end)
    end,
  })

  if job <= 0 then
    M.close()
    notify("kumeyuri: failed to start terminal job", vim.log.levels.ERROR)
    return nil
  end

  state.buf = buf
  state.win = win
  state.job = job
  if cfg.start_insert then
    vim.cmd("startinsert")
  end
  return vim.deepcopy(state)
end

function M.setup(opts)
  config = vim.tbl_deep_extend("force", vim.deepcopy(defaults), opts or {})
  pcall(vim.api.nvim_del_user_command, "KumeyuriPreview")
  pcall(vim.api.nvim_del_user_command, "KumeyuriClose")

  vim.api.nvim_create_user_command("KumeyuriPreview", function(args)
    M.open({
      file = args.args ~= "" and args.args or nil,
    })
  end, {
    nargs = "?",
    complete = "file",
    desc = "Open kumeyuri play in a floating terminal",
  })

  vim.api.nvim_create_user_command("KumeyuriClose", function()
    M.close()
  end, {
    desc = "Close the active kumeyuri preview",
  })
end

return M
