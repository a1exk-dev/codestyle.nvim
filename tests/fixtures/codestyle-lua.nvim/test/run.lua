-- The test entry of the fake plugin, as in a Language Plugin repo (ADR-0013):
--
--   nvim --headless -u tests/minimal_init.lua -l tests/fixtures/codestyle-lua.nvim/test/run.lua
--
-- A real plugin's `test/run.lua` clones its dependencies first; here the
-- Core's test init puts the Core on the runtimepath.

local plugin = vim.fs.dirname(vim.fs.dirname(vim.fs.normalize(vim.fn.fnamemodify(_G.arg[0], ':p'))))
vim.opt.runtimepath:append(plugin)

require('codestyle.testing').main({
  language = 'lua',
  corpus_dir = plugin .. '/test/corpus',
  cases_dir = plugin .. '/test/cases',
  expected_failures = dofile(plugin .. '/test/expected_failures.lua'),
})
