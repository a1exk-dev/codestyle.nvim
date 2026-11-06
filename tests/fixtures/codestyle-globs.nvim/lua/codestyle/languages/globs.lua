-- A fake (ADR-0017) whose `match(buf)` claims `phpunit.xml.dist`-style names
-- through the Core helper `match_globs` (ADR-0015). Its filetype `globs` is
-- one no buffer gets by itself.
-- It formats with the fake `lua` plugin's formatter, so that plugin must be
-- on the runtimepath too.

local globs = require('codestyle').match_globs({ 'phpunit.xml.dist', '*.es6' })

---@type codestyle.Spec
return {
  api = 1,
  id = 'globs',
  name = 'globs',
  filetypes = { 'globs' },
  parsers = { default = { 'lua' } },
  match = function(buf)
    -- Counts the calls, so a test can tell that `match` was not asked.
    vim.g.codestyle_test_match_calls = (vim.g.codestyle_test_match_calls or 0) + 1
    return globs(buf)
  end,
  options = {
    { key = 'spaces.around_assignment', type = 'boolean', default = false, label = 'Assignment operators (=)' },
  },
  formatter = 'codestyle.languages.lua.formatter',
}
