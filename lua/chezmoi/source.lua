local M = {}

local function source_config(name)
  local source = require("chezmoi").config.sources[name]
  if source == nil then
    error("Unknown chezmoi source: " .. name)
  end
  if type(source.path) ~= "string" or source.path == "" then
    error("Chezmoi source " .. name .. " requires a path")
  end
  return source
end

---@param name? string
---@return { name: string, path: string?, global_args: string[] }
function M.get(name)
  if name == nil then
    return { name = "default", global_args = {} }
  end

  local source = source_config(name)
  local path = vim.fn.expand(source.path)
  local global_args = { "--source", path }
  vim.list_extend(global_args, source.global_args or {})
  return {
    name = name,
    path = path,
    global_args = global_args,
  }
end

---@param names? string[]
---@return { name: string, path: string?, global_args: string[] }[]
function M.all(names)
  if names ~= nil then
    local sources = {}
    for _, name in ipairs(names) do
      table.insert(sources, M.get(name))
    end
    return sources
  end

  local sources = { M.get() }
  local names_from_config = vim.tbl_keys(require("chezmoi").config.sources)
  table.sort(names_from_config)
  for _, name in ipairs(names_from_config) do
    table.insert(sources, M.get(name))
  end
  return sources
end

return M
