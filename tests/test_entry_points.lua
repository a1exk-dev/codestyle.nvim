-- The entry points of ADR-0014: the key, `gq`, the command with a range and
-- the conform.nvim formatter. Each test formats a real buffer and reads the
-- lines back.

local H = dofile('tests/helpers.lua')
local expect = MiniTest.expect

local child = H.new_child()

local T = MiniTest.new_set({
  hooks = {
    pre_case = function()
      child:setup()
      child:write_global({ version = 1, languages = { lua = { spaces = { around_assignment = true } } } })
    end,
    post_case = function()
      child:teardown()
    end,
  },
})

local three_lines = { 'x=1', 'y=2', 'z=3' }

T[':Codestyle format'] = MiniTest.new_set()

T[':Codestyle format']['with a range formats only those lines'] = function()
  local buf = child:open_buffer({ filetype = 'lua', lines = three_lines })

  child.cmd('2,3Codestyle format')

  expect.equality(child:lines(buf), { 'x=1', 'y = 2', 'z = 3' })
end

T[':Codestyle format']['with no range formats the whole file'] = function()
  local buf = child:open_buffer({ filetype = 'lua', lines = three_lines })
  child.api.nvim_win_set_cursor(0, { 2, 0 })

  child.cmd('Codestyle format')

  expect.equality(child:lines(buf), { 'x = 1', 'y = 2', 'z = 3' })
end

--- Restarts the child with these `--cmd` lines, for a user's early config.
---@param cmd string[]
local function restart_with(cmd)
  child:teardown()
  child:setup({ cmd = cmd })
  child:write_global({ version = 1, languages = { lua = { spaces = { around_assignment = true } } } })
end

T['the key'] = MiniTest.new_set()

T['the key']['<Plug>(codestyle-format) formats the buffer in Normal mode'] = function()
  local buf = child:open_buffer({ filetype = 'lua', lines = three_lines })

  child.type_keys('<Plug>(codestyle-format)')

  expect.equality(child:lines(buf), { 'x = 1', 'y = 2', 'z = 3' })
end

T['the key']['<leader>cf formats the selected lines in Visual mode'] = function()
  local buf = child:open_buffer({ filetype = 'lua', lines = three_lines })

  child.type_keys('j', 'V', 'j', '\\cf')

  expect.equality(child:lines(buf), { 'x=1', 'y = 2', 'z = 3' })
  expect.equality(child.fn.mode(), 'n')
end

T['the key']['a charwise selection formats its whole lines'] = function()
  local buf = child:open_buffer({ filetype = 'lua', lines = three_lines })

  child.type_keys('j', 'l', 'v', 'j', '\\cf')

  expect.equality(child:lines(buf), { 'x=1', 'y = 2', 'z = 3' })
end

T['the key']['a blockwise selection is refused with a notice'] = function()
  local buf = child:open_buffer({ filetype = 'lua', lines = three_lines })

  child.type_keys('<C-v>', 'j', '\\cf')

  expect.equality(child:lines(buf), three_lines)
  expect.equality(child.fn.mode(), 'n')
  expect.equality(child:notices(), {
    {
      level = H.levels.WARN,
      message = 'codestyle: a blockwise selection cannot be formatted; select whole lines with V',
    },
  })
end

T['the key']['<leader>cf is mapped in Normal and Visual mode'] = function()
  expect.equality(child.fn.maparg('<leader>cf', 'n'), '<Plug>(codestyle-format)')
  expect.equality(child.fn.maparg('<leader>cf', 'x'), '<Plug>(codestyle-format)')
end

T['the key']['<leader>cf is not mapped when the user mapped it before'] = function()
  restart_with({ 'nnoremap <leader>cf <Cmd>let g:mine = 1<CR>' })

  expect.equality(child.fn.maparg('<leader>cf', 'n'), '<Cmd>let g:mine = 1<CR>')
  expect.equality(child.fn.maparg('<leader>cf', 'x'), '<Plug>(codestyle-format)')
end

T['the key']['<leader>cf follows a mapleader set in the user config'] = function()
  restart_with({ 'let mapleader = " "' })

  expect.equality(child.fn.maparg('<Space>cf', 'n'), '<Plug>(codestyle-format)')
end

T['the key']['setup{ keys = false } removes the default key'] = function()
  child.lua('require("codestyle").setup({ keys = false })')

  expect.equality(child.fn.maparg('<leader>cf', 'n'), '')
  expect.equality(child.fn.maparg('<leader>cf', 'x'), '')
  expect.no_equality(child.fn.maparg('<Plug>(codestyle-format)', 'n'), '')
end

T['the key']['setup{ keys = false } before the plugin loads maps no key'] = function()
  local root = vim.fn.getcwd()
  restart_with({ 'set rtp^=' .. root, 'lua require("codestyle").setup({ keys = false })' })

  expect.equality(child.fn.maparg('<leader>cf', 'n'), '')
end

local ours = "v:lua.require'codestyle'.formatexpr()"

---@param buf integer
---@param name string
local function get(buf, name)
  return child.api.nvim_get_option_value(name, { buf = buf })
end

---@param buf integer
---@param name string
---@param value any
local function set(buf, name, value)
  child.api.nvim_set_option_value(name, value, { buf = buf })
end

T['gq'] = MiniTest.new_set()

T['gq']['a claimed buffer gets the Core formatexpr on FileType'] = function()
  local buf = child:open_buffer({ filetype = 'lua', lines = three_lines })

  expect.equality(get(buf, 'formatexpr'), ours)
end

T['gq']['an unclaimed buffer keeps an empty formatexpr'] = function()
  local buf = child:open_buffer({ filetype = 'text', lines = three_lines })

  expect.equality(get(buf, 'formatexpr'), '')
end

T['gq']['a formatexpr that is already set stays'] = function()
  child.o.formatexpr = 'MyFormat()'
  local buf = child:open_buffer({ filetype = 'lua', lines = three_lines })

  expect.equality(get(buf, 'formatexpr'), 'MyFormat()')
end

T['gq']['a buffer that becomes unclaimed loses only the Core formatexpr'] = function()
  local buf = child:open_buffer({ filetype = 'lua', lines = three_lines })
  set(buf, 'filetype', 'text')
  expect.equality(get(buf, 'formatexpr'), '')

  set(buf, 'filetype', 'lua')
  set(buf, 'formatexpr', 'Other()')
  set(buf, 'filetype', 'text')
  expect.equality(get(buf, 'formatexpr'), 'Other()')
end

T['gq']['gq formats the lines through the Core'] = function()
  local buf = child:open_buffer({ filetype = 'lua', lines = three_lines })

  child.type_keys('j', 'gqj')

  expect.equality(child:lines(buf), { 'x=1', 'y = 2', 'z = 3' })
end

T['gq']['Insert mode leaves wrapping at textwidth to Neovim'] = function()
  local buf = child:open_buffer({ filetype = 'lua', lines = { '' } })
  set(buf, 'textwidth', 10)
  set(buf, 'formatoptions', 't')

  child.type_keys('i', 'aaaa bbbb cccc dddd', '<Esc>')

  expect.equality(child:lines(buf), { 'aaaa bbbb', 'cccc dddd' })
end

--- Loads conform.nvim after startup, as lazy.nvim does, with this setup.
---@param setup table
local function lazy_load_conform(setup)
  child.lua(
    [[
      require('conform').setup(...)
      vim.api.nvim_exec_autocmds('User', { pattern = 'LazyLoad', data = 'conform.nvim' })
    ]],
    { setup }
  )
end

T['conform'] = MiniTest.new_set()

T['conform']['codestyle is in conform.formatters and formatters_by_ft is untouched'] = function()
  lazy_load_conform({ formatters_by_ft = { lua = { 'stylua' } } })

  expect.equality(child.lua_get('type(require("conform").formatters.codestyle)'), 'table')
  expect.equality(child.lua_get('require("conform").formatters_by_ft'), { lua = { 'stylua' } })
end

T['conform']['conform loaded during startup gets codestyle too'] = function()
  local root = vim.fn.getcwd()
  restart_with({ 'set rtp+=' .. root .. '/.tests/conform.nvim', 'lua require("conform").setup({})' })

  expect.equality(child.lua_get('type(require("conform").formatters.codestyle)'), 'table')
end

T['conform']['formats the buffer'] = function()
  lazy_load_conform({ formatters_by_ft = { lua = { 'codestyle' } } })
  local buf = child:open_buffer({ filetype = 'lua', lines = three_lines })

  child.lua('require("conform").format({ bufnr = ... })', { buf })

  expect.equality(child:lines(buf), { 'x = 1', 'y = 2', 'z = 3' })
end

T['conform']['formats the lines conform passes, after an earlier formatter'] = function()
  child.lua([[
    require('conform').formatters.rename = {
      format = function(_, _, lines, callback)
        callback(nil, vim.tbl_map(function(line) return (line:gsub('^x', 'value')) end, lines))
      end,
    }
  ]])
  lazy_load_conform({ formatters_by_ft = { lua = { 'rename', 'codestyle' } } })
  local buf = child:open_buffer({ filetype = 'lua', lines = three_lines })

  child.lua('require("conform").format({ bufnr = ... })', { buf })

  expect.equality(child:lines(buf), { 'value = 1', 'y = 2', 'z = 3' })
end

T['conform']['keeps the range'] = function()
  lazy_load_conform({ formatters_by_ft = { lua = { 'codestyle' } } })
  local buf = child:open_buffer({ filetype = 'lua', lines = three_lines })

  child.lua('require("conform").format({ bufnr = ..., range = { start = { 2, 0 }, ["end"] = { 2, 3 } } })', { buf })

  expect.equality(child:lines(buf), { 'x=1', 'y = 2', 'z=3' })
end

T['conform']['is unavailable for an unclaimed buffer and for a missing parser'] = function()
  child:teardown()
  child:setup({ plugins = { 'codestyle-lua.nvim', 'codestyle-parsers.nvim' } })
  lazy_load_conform({})
  local info = 'require("conform").get_formatter_info("codestyle", ...).available'

  expect.equality(child.lua_get(info, { child:open_buffer({ filetype = 'lua', lines = three_lines }) }), true)
  expect.equality(child.lua_get(info, { child:open_buffer({ filetype = 'text', lines = three_lines }) }), false)
  expect.equality(child.lua_get(info, { child:open_buffer({ filetype = 'noparser', lines = three_lines }) }), false)
  expect.equality(child:notices(), {})
end

return T
