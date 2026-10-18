local base = require "chezmoi.commands.__base"

describe("commands.__base.execute", function()
  it("starts asynchronous commands without waiting for completion", function()
    local temp_dir = vim.fn.tempname()
    local bin_dir = temp_dir .. "/bin"
    local chezmoi_path = bin_dir .. "/chezmoi"
    local previous_path = vim.env.PATH

    vim.fn.mkdir(bin_dir, "p")
    vim.fn.writefile({ "#!/bin/sh", "sleep 0.2" }, chezmoi_path)
    vim.fn.setfperm(chezmoi_path, "rwxr-xr-x")
    vim.env.PATH = bin_dir .. ":" .. previous_path

    local started_at = vim.uv.hrtime()
    local job = base.execute {
      cmd = "apply",
      async = true,
      on_stderr = function() end,
    }
    local elapsed_ms = (vim.uv.hrtime() - started_at) / 1000000

    assert.is_true(elapsed_ms < 100)
    assert.is_nil(job.is_shutdown)
    assert.is_true(vim.wait(1000, function()
      return job.is_shutdown
    end))

    vim.env.PATH = previous_path
    vim.fn.delete(temp_dir, "rf")
  end)
end)
