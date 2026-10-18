local edit_cmd = require("chezmoi.commands.__edit")
local util = require("chezmoi.util")

describe("Test __edit.__parse_custom_opts", function()
  local test_results = {}

  it("Should return 'watch=true' when --watch given", function()
    local input = { "--watch" }
    local expected = {
      watch = true
    }

    local actual = edit_cmd.__parse_custom_opts(input)
    table.insert(test_results, { expected, actual })
  end)

  it("Should return 'watch=false' when --watch not given", function()
    local input = {}
    local expected = {
      watch = false
    }

    local actual = edit_cmd.__parse_custom_opts(input)
    table.insert(test_results, { expected, actual })
  end)

  it("Should remove '--watch' flag when given", function()
    local input = { "--watch" }
    local expected = 0
    local _ = edit_cmd.__parse_custom_opts(input)
    local actual = #input
    table.insert(test_results, { expected, actual })
  end)

  for _, v in pairs(test_results) do
    assert(v.expected == v.actual)
  end
end)

-- Add test cases for the ignore patterns functionality

describe("util.str_matches_any_of", function()
  local util = require("chezmoi.util")
  
  it("should match run_onchange files", function()
    local filename = "run_onchange_install_packages.sh"
    local patterns = {"run_onchange_.*"}
    assert.is_true(util.str_matches_any_of(filename, patterns))
  end)
  
  it("should match .chezmoiignore files", function()
    local filename = ".chezmoiignore"
    local patterns = {"%.chezmoiignore"}
    assert.is_true(util.str_matches_any_of(filename, patterns))
  end)
  
  it("should not match regular files", function()
    local filename = "dot_vimrc"
    local patterns = {"run_onchange_.*", "%.chezmoiignore"}
    assert.is_false(util.str_matches_any_of(filename, patterns))
  end)
  
  it("should return false with empty patterns", function()
    local filename = "run_onchange_test.sh"
    local patterns = {}
    assert.is_false(util.str_matches_any_of(filename, patterns))
  end)
  
  it("should return false with nil patterns", function()
    local filename = "run_onchange_test.sh"
    assert.is_false(util.str_matches_any_of(filename, nil))
  end)
end)

describe("commands.__edit.watch", function()
  it("applies in the background and serializes rapid saves", function()
    local temp_dir = vim.fn.tempname()
    local bin_dir = temp_dir .. "/bin"
    local chezmoi_path = bin_dir .. "/chezmoi"
    local source_path = temp_dir .. "/source"
    local second_source_path = temp_dir .. "/second-source"
    local log_path = temp_dir .. "/apply.log"
    local previous_path = vim.env.PATH
    local previous_log_path = vim.env.CHEZMOI_NVIM_SMOKE_LOG

    vim.fn.mkdir(bin_dir, "p")
    vim.fn.writefile({
      "#!/bin/sh",
      "if [ \"$1\" = \"apply\" ]; then",
      "  if [ -e \"$CHEZMOI_NVIM_SMOKE_LOG.lock\" ]; then",
      "    echo concurrent >> \"$CHEZMOI_NVIM_SMOKE_LOG\"",
      "  fi",
      "  touch \"$CHEZMOI_NVIM_SMOKE_LOG.lock\"",
      "  sleep 0.2",
      "  rm \"$CHEZMOI_NVIM_SMOKE_LOG.lock\"",
      "  echo apply >> \"$CHEZMOI_NVIM_SMOKE_LOG\"",
      "fi",
    }, chezmoi_path)
    vim.fn.setfperm(chezmoi_path, "rwxr-xr-x")
    vim.fn.writefile({ "first" }, source_path)
    vim.fn.writefile({ "first" }, second_source_path)
    vim.env.PATH = bin_dir .. ":" .. previous_path
    vim.env.CHEZMOI_NVIM_SMOKE_LOG = log_path

    vim.cmd.edit(source_path)
    local bufnr = vim.api.nvim_get_current_buf()
    edit_cmd.watch(bufnr)

    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "second" })
    local started_at = vim.uv.hrtime()
    vim.cmd.write()
    local elapsed_ms = (vim.uv.hrtime() - started_at) / 1000000
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "third" })
    vim.cmd.write()

    vim.cmd.edit(second_source_path)
    local second_bufnr = vim.api.nvim_get_current_buf()
    edit_cmd.watch(second_bufnr)
    vim.api.nvim_buf_set_lines(second_bufnr, 0, -1, false, { "second" })
    vim.cmd.write()

    assert.is_true(elapsed_ms < 100)
    assert.is_true(vim.wait(2000, function()
      return vim.fn.filereadable(log_path) == 1 and #vim.fn.readfile(log_path) == 3
    end))
    assert.is_false(vim.tbl_contains(vim.fn.readfile(log_path), "concurrent"))

    vim.api.nvim_clear_autocmds { group = "chezmoi", buffer = bufnr }
    vim.api.nvim_clear_autocmds { group = "chezmoi", buffer = second_bufnr }
    vim.env.PATH = previous_path
    vim.env.CHEZMOI_NVIM_SMOKE_LOG = previous_log_path
    vim.fn.delete(temp_dir, "rf")
  end)
end)
