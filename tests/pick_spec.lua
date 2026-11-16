describe("chezmoi.pick.snacks", function()
  it("combines configured sources and retains the source on selection", function()
    local chezmoi = require("chezmoi")
    local original_commands = package.loaded["chezmoi.commands"]
    local original_snacks = _G.Snacks
    local commands = {}
    local picker

    chezmoi.setup({
      sources = {
        personal = { path = "~/personal-chezmoi" },
      },
    })
    package.loaded["chezmoi.commands"] = {
      list = function(opts)
        table.insert(commands, { command = "list", global_args = opts.global_args })
        return { (opts.global_args[2] or "default") .. "/dot_file" }
      end,
      edit = function(opts)
        table.insert(commands, { command = "edit", global_args = opts.global_args })
      end,
    }
    _G.Snacks = {
      picker = {
        pick = function(opts)
          picker = opts
        end,
      },
    }

    package.loaded["chezmoi.pick"] = nil
    require("chezmoi.pick").snacks()

    assert.are.same({}, commands[1].global_args)
    assert.are.same({ "--source", vim.fn.expand("~/personal-chezmoi") }, commands[2].global_args)
    assert.are.equal(2, #picker.items)
    picker.confirm({ close = function() end }, picker.items[2])
    assert.are.same({ "--source", vim.fn.expand("~/personal-chezmoi") }, commands[3].global_args)

    package.loaded["chezmoi.commands"] = original_commands
    package.loaded["chezmoi.pick"] = nil
    _G.Snacks = original_snacks
  end)
end)
