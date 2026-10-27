local Path = require "plenary.path"
local config = require("chezmoi").config
local notify = require "chezmoi.notify"
local util = require "chezmoi.util"
local apply = require "chezmoi.commands.__apply"
local status = require "chezmoi.commands.__status"
local base = require "chezmoi.commands.__base"
local log = require "chezmoi.log"

local M = {}

local apply_running = false
local pending_applies = {}
local queued_source_paths = {}

local function command_error(request, step, exit_code, stderr)
  local details = table.concat(stderr):gsub("%s+$", "")
  if details == "" then
    details = "no error output"
  end
  notify.error(string.format("chezmoi %s failed for %s (exit %d): %s", step, request.source_path, exit_code, details))
end

local run_next_apply

local function run_command(request, step, cmd, args, on_success)
  local stderr = {}
  base.execute {
    cmd = cmd,
    args = args,
    global_args = request.global_args,
    async = true,
    on_stderr = function(_, data)
      if data and data ~= "" then
        table.insert(stderr, data)
      end
    end,
    on_exit = function(_, exit_code)
      if exit_code == 0 then
        on_success()
      else
        command_error(request, step, exit_code, stderr)
        run_next_apply()
      end
    end,
  }
end

run_next_apply = function()
  local request = table.remove(pending_applies, 1)
  if not request then
    apply_running = false
    return
  end

  queued_source_paths[request.source_path] = nil
  apply_running = true

  local apply_args = { "--source-path", request.source_path }
  if request.force then
    table.insert(apply_args, "--force")
  end

  run_command(request, "apply", "apply", apply_args, function()
    run_command(request, "git add", "git", { "--", "add", "--", request.source_path }, function()
      run_command(request, "git commit", "git", { "--", "commit", "-m", "Update chezmoi source", "--", request.source_path }, function()
        run_command(request, "git push", "git", { "--", "push" }, function()
          local on_apply_conf = config.events.on_apply
          if on_apply_conf.notification.enable then
            notify.info(on_apply_conf.notification.msg, on_apply_conf.notification.opts)
          end
          run_next_apply()
        end)
      end)
    end)
  end)
end

local function queue_apply(source_path, bufnr, opts)
  if queued_source_paths[source_path] then
    return
  end

  queued_source_paths[source_path] = true
  table.insert(pending_applies, {
    source_path = source_path,
    bufnr = bufnr,
    force = opts.force,
    global_args = opts.global_args,
  })

  if not apply_running then
    run_next_apply()
  end
end

---@param args string[]
---@return table { watch: boolean, force: boolean }
function M.__parse_custom_opts(args)
  local ret = {
    watch = config.edit.watch,
    force = config.edit.force,
  }

  local pos = util.__arr_find_first_one_of(args, { "--watch" })
  if pos ~= nil then
    ret.watch = true
    table.remove(args, pos)
  end

  pos = util.__arr_find_first_one_of(args, { "--force" })
  if pos ~= nil then
    ret.force = true
    table.remove(args, pos)
  end

  return ret
end

---@param bufnr number?
---@param opts? { force?: boolean, global_args?: string[] }
function M.watch(bufnr, opts)
  -- Use autocmd to make it work as if 'watch' option is given
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  if type(opts) == "boolean" then
    opts = { force = opts }
  end
  opts = opts or {}
  opts.force = opts.force or config.edit.force
  opts.global_args = opts.global_args or {}

  local source_path = vim.api.nvim_buf_get_name(bufnr)
  local should_ignore = util.str_matches_any_of(
    vim.fn.fnamemodify(source_path, ":t"),
    config.edit.ignore_patterns
  )
  if should_ignore then
    log.info("Skipping watch setup for ignored file: " .. vim.fn.fnamemodify(source_path, ":t"))
    return
  end

  local status_err = nil
  status.execute {
    args = { "--source-path", source_path },
    global_args = opts.global_args,
    on_stderr = function(_, data)
      status_err = data
    end,
  }

  if status_err then
    notify.error("chezmoi status failed for " .. source_path .. ": " .. status_err)
    return
  end

  local event = { "BufWritePost" }
  local augroup = vim.api.nvim_create_augroup("chezmoi", { clear = false })
  local autocmds = vim.api.nvim_get_autocmds {
    event = event,
    group = augroup,
    buffer = bufnr,
  }

  local on_watch_conf = config.events.on_watch
  local on_watch_func = function(_)
    if on_watch_conf.notification.enable then
      notify.info(on_watch_conf.notification.msg, on_watch_conf.notification.opts)
    end
  end

  if on_watch_conf.override ~= nil and type(on_watch_conf.override) == "function" then
    on_watch_func = on_watch_conf.override
  end

  if #autocmds == 0 then
    on_watch_func(bufnr)
  end

  vim.api.nvim_clear_autocmds {
    event = event,
    group = augroup,
    buffer = bufnr,
  }

  vim.api.nvim_create_autocmd(event, {
    group = augroup,
    buffer = bufnr,
    callback = function()
      queue_apply(source_path, bufnr, opts)
    end,
  })
end

---@param opts { targets?: any, args: string[]? }
function M.execute(opts)
  opts = opts or {}
  opts.targets = vim.iter({ opts.targets or {} }):flatten():totable()
  local custom_opts = M.__parse_custom_opts(opts.args or {})

  if vim.tbl_isempty(opts.targets) then
    notify.panic "Failed to resolve positional arguments. Please specify target files."
    return
  end

  for _, target in ipairs(opts.targets) do
    local path = Path:new(target)
    local source_path_res = base.execute {
      cmd = "source-path",
      targets = { tostring(path) },
      on_stderr = function() end,
    }

    if not source_path_res or vim.tbl_isempty(source_path_res) then
      notify.panic("Error while querying source file path for '" .. tostring(path) .. "'")
      return
    end

    local source_path = source_path_res[1]

    local on_open_conf = config.events.on_open
    local on_open_func = function(_)
      if on_open_conf.notification.enable then
        notify.info(on_open_conf.notification.msg, on_open_conf.notification.opts)
      end
    end

    if on_open_conf.override ~= nil and type(on_open_conf.override) == "function" then
      on_open_func = on_open_conf.override
    end

    local ok, _ = pcall(vim.cmd.edit, source_path)
    if ok then
      on_open_func(bufnr)
    else
      notify.panic("Failed to open file " .. source_path)
      return
    end

    if custom_opts.watch then
      local bufnr = vim.api.nvim_get_current_buf()
      M.watch(bufnr, custom_opts.force)
    end
  end
end

return M
