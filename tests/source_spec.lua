local chezmoi = require("chezmoi")
local source = require("chezmoi.source")

describe("chezmoi sources", function()
  it("keeps the default source and adds configured sources", function()
    chezmoi.setup({
      sources = {
        personal = {
          path = "~/personal-chezmoi",
          global_args = { "--persistent-state", "~/state.db" },
        },
      },
    })

    local sources = source.all()
    assert.are.equal("default", sources[1].name)
    assert.are.equal("personal", sources[2].name)
    assert.are.equal(vim.fn.expand("~/personal-chezmoi"), sources[2].path)
    local autocmds = vim.api.nvim_get_autocmds({ event = "BufReadPost", group = "chezmoi_sources" })
    assert.are.equal(1, #autocmds)
    assert.are.equal(vim.fn.expand("~/personal-chezmoi") .. "/**", autocmds[1].pattern)
    assert.are.same({
      "--source",
      vim.fn.expand("~/personal-chezmoi"),
      "--persistent-state",
      "~/state.db",
    }, sources[2].global_args)
  end)
end)
