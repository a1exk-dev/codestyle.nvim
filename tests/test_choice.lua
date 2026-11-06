-- Choosing the Language Plugin and parser for a buffer (ADR-0015): the
-- user's override, then the filetype claim, then `match(buf)`.
--
-- The fake `lua` plugin formats `x =1` as `x = 1` with the Code Style below,
-- and every other fake formats it as `x=1` (its default), so the lines tell
-- which plugin formatted the buffer.

local H = dofile('tests/helpers.lua')
local expect = MiniTest.expect

local child = H.new_child()

local T = MiniTest.new_set({
  hooks = {
    post_case = function()
      child:teardown()
    end,
  },
})

---@param plugins string[]
local function setup(plugins)
  child:setup({ plugins = vim.list_extend({ 'codestyle-lua.nvim' }, plugins) })
  child:write_global({ version = 1, languages = { lua = { spaces = { around_assignment = true } } } })
end

---@param opts { filetype?: string, name?: string }
---@return string[] lines the buffer's lines after one format
local function format(opts)
  local buf = child:open_buffer({ filetype = opts.filetype, name = opts.name, lines = { 'x =1' } })
  child:format({ buf = buf })
  return child:lines(buf)
end

local by_lua, by_other, unformatted = { 'x = 1' }, { 'x=1' }, { 'x =1' }

T['override'] = MiniTest.new_set()

T['override']['setup{ filetypes } beats the filetype claim'] = function()
  setup({ 'codestyle-alt.nvim' })
  child.lua('require("codestyle").setup({ filetypes = { lua = "alt" } })')

  expect.equality(format({ filetype = 'lua' }), by_other)
end

T['override']['vim.b.codestyle_language beats setup{ filetypes }'] = function()
  setup({ 'codestyle-alt.nvim' })
  child.lua('require("codestyle").setup({ filetypes = { lua = "alt" } })')
  local buf = child:open_buffer({ filetype = 'lua', lines = { 'x =1' } })
  child.api.nvim_buf_set_var(buf, 'codestyle_language', 'lua')

  child:format({ buf = buf })

  expect.equality(child:lines(buf), by_lua)
end

T['override']['filetypes = { x = false } formats nothing'] = function()
  setup({})
  child.lua('require("codestyle").setup({ filetypes = { lua = false } })')

  expect.equality(format({ filetype = 'lua' }), unformatted)
  expect.equality(child:notices(), {})
end

T['override']['a filetype that setup{} does not name keeps its claim'] = function()
  setup({ 'codestyle-alt.nvim' })
  child.lua('require("codestyle").setup({ filetypes = { alt = "lua" } })')

  expect.equality(format({ filetype = 'lua' }), by_lua)
end

T['match'] = MiniTest.new_set()

T['match']['match(buf) claims a phpunit.xml.dist-style name with no filetype'] = function()
  setup({ 'codestyle-globs.nvim' })

  expect.equality(format({ name = 'phpunit.xml.dist' }), by_other)
end

T['match']['match(buf) claims a name whose filetype no spec lists'] = function()
  setup({ 'codestyle-globs.nvim' })

  expect.equality(format({ filetype = 'xml', name = 'app.es6' }), by_other)
end

T['match']['match(buf) is not asked when a spec lists the filetype'] = function()
  setup({ 'codestyle-globs.nvim' })

  expect.equality(format({ filetype = 'lua', name = 'phpunit.xml.dist' }), by_lua)
  expect.equality(child.g.codestyle_test_match_calls, vim.NIL)
end

T['match']['a name that no glob matches stays unclaimed'] = function()
  setup({ 'codestyle-globs.nvim' })

  expect.equality(format({ name = 'phpunit.xml.dist.bak' }), unformatted)
  expect.equality(child:notices(), {
    { level = H.levels.WARN, message = 'codestyle: no Language Plugin claims the filetype ""' },
  })
end

T['conflict'] = MiniTest.new_set()

T['conflict']['two specs that claim one filetype format nothing, with one WARN per filetype'] = function()
  setup({ 'codestyle-lua-rival.nvim' })

  expect.equality(format({ filetype = 'lua' }), unformatted)
  expect.equality(format({ filetype = 'lua' }), unformatted)
  expect.equality(child:notices(), {
    {
      level = H.levels.WARN,
      message = 'codestyle: codestyle-lua.nvim and codestyle-lua-rival.nvim both claim the filetype "lua", '
        .. 'so none formats it; pick one with setup{ filetypes = { ["lua"] = "lua" } }',
    },
  })
end

T['conflict']['the setup line it names settles the conflict'] = function()
  setup({ 'codestyle-lua-rival.nvim' })
  child.lua('require("codestyle").setup({ filetypes = { lua = "lua" } })')

  expect.equality(format({ filetype = 'lua' }), by_lua)
end

T['dotted filetype'] = MiniTest.new_set()

T['dotted filetype']['lua.fake falls back to the plugin of lua'] = function()
  setup({})

  expect.equality(format({ filetype = 'lua.fake' }), by_lua)
end

T['dotted filetype']['a spec that lists lua.fake claims it before the plugin of lua'] = function()
  setup({ 'codestyle-lua-fake.nvim' })

  expect.equality(format({ filetype = 'lua.fake' }), by_other)
end

T['parser'] = MiniTest.new_set()

T['parser']['the first installed parser of the list is used'] = function()
  setup({ 'codestyle-parsers.nvim' })

  expect.equality(format({ filetype = 'firstparser' }), by_other)
  expect.equality(child:notices(), {})
end

T['parser']['no installed parser gives one WARN per buffer and language that says what to install'] = function()
  setup({ 'codestyle-parsers.nvim' })
  local buf = child:open_buffer({ filetype = 'noparser', lines = { 'x =1' } })

  child:format({ buf = buf })
  child:format({ buf = buf })

  expect.equality(child:lines(buf), unformatted)
  expect.equality(child:notices(), {
    {
      level = H.levels.WARN,
      message = 'codestyle: codestyle-parsers.nvim has no Tree-sitter parser for this buffer; '
        .. 'install one of: no_such_parser_a, no_such_parser_b',
    },
  })
end

return T
