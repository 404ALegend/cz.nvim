local chezmoi = {}

local default_config = {
  extra_args = {},
  sources = {},
  edit = {
    watch = false,
    force = false,
    ignore_patterns = {
      "run_onchange_.*",
      "run_once_.*", 
      "%.chezmoiignore",
      "%.chezmoitemplate",
      "%.chezmoiexternal.*",
      "%.chezmoiroot",
      "%.chezmoiversion",
    },
  },
  events = {
    on_open = {
      notification = {
        enable = true,
        msg = "Opened a chezmoi-managed file",
        opts = {},
      },
    },
    on_watch = {
      notification = {
        enable = true,
        msg = "This file will be automatically applied",
        opts = {},
      },
    },
    on_apply = {
      notification = {
        enable = true,
        msg = "Successfully applied",
        opts = {},
      },
    },
  },
  telescope = {
    select = { "<CR>" },
  },
}

local function register_source_watchers()
  local group = vim.api.nvim_create_augroup("chezmoi_sources", { clear = true })
  local names = vim.tbl_keys(chezmoi.config.sources)
  table.sort(names)
  for _, name in ipairs(names) do
    local source = require("chezmoi.source").get(name)
    vim.api.nvim_create_autocmd({ "BufRead", "BufNewFile" }, {
      group = group,
      pattern = source.path .. "/**",
      callback = function(ev)
        require("chezmoi.commands.__edit").watch(ev.buf, { source = source.name })
      end,
    })
  end
end

function chezmoi.setup(opts)
  local config = vim.tbl_deep_extend("force", default_config, opts)
  chezmoi.config = config
  register_source_watchers()
  vim.g.chezmoi_setup = 1
end

if vim.g.chezmoi_setup ~= 1 then
  chezmoi.config = default_config
end

return chezmoi
