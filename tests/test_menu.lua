-- The Menu shell and the Preview (ADR-0004, ADR-0016): tested in a child
-- Neovim through `:Codestyle`, keys and clicks, and read back from the panes'
-- text, window options, notices and a few reference screenshots.

local H = dofile('tests/helpers.lua')
local M = dofile('tests/menu_helpers.lua')
local expect = MiniTest.expect

local child = H.new_child()

local T = MiniTest.new_set({
  hooks = {
    pre_case = function()
      M.setup(child, { 'codestyle-lua.nvim', 'codestyle-broken.nvim' })
    end,
    post_case = function()
      child:teardown()
    end,
  },
})

local function settle()
  M.settle(child)
end

local function open_menu()
  M.open_menu(child)
end

---@param name string
local function pane_win(name)
  return M.pane_win(child, name)
end

---@param name string
local function pane_lines(name)
  return M.pane_lines(child, name)
end

---@param name string
local function pane_rows(name)
  return M.pane_rows(child, name)
end

---@param name string
---@param text string
local function cursor_on(name, text)
  M.cursor_on(child, name, text)
end

--- The floating windows, by the filetype of their buffer.
---@return string[]
local function float_filetypes()
  return child.lua([[
    local fts = {}
    for _, win in ipairs(vim.api.nvim_list_wins()) do
      if vim.api.nvim_win_get_config(win).relative ~= '' then
        table.insert(fts, vim.bo[vim.api.nvim_win_get_buf(win)].filetype)
      end
    end
    table.sort(fts)
    return fts
  ]])
end

local function menu_title()
  return child.lua([[
    for _, win in ipairs(vim.api.nvim_list_wins()) do
      local title = vim.api.nvim_win_get_config(win).title
      if title then
        return table.concat(vim.tbl_map(function(chunk) return chunk[1] end, title))
      end
    end
  ]])
end

T['opens three floats over a backdrop with the language list'] = function()
  child:write_global({ version = 1, languages = { gone = { a = 1, b = { c = 2 } } } })
  open_menu()

  local fts = float_filetypes()
  expect.equality(vim.list_contains(fts, 'snacks_win_backdrop'), true)
  expect.equality(pane_win('languages') ~= nil, true)
  expect.equality(pane_win('options') ~= nil, true)
  expect.equality(pane_win('preview') ~= nil, true)
  expect.equality(pane_lines('languages'), {
    'Global Code Style',
    '',
    'General',
    'Broken',
    'Lua',
    '',
    '⚠ gone: not installed, 2 kept values',
  })
  expect.equality(child:notices(), {})
end

---@param name string
local function winbar_text(name)
  return M.winbar_text(child, name)
end

T['moving in the language list switches the language and the title shows scope and path'] = function()
  open_menu()
  expect.equality(menu_title(), ' General · Global Code Style · ~/xdg/config/nvim/codestyle.json ')
  expect.equality(pane_rows('options'), { 'Hard wrap at [ 120 ]' })

  cursor_on('languages', 'Lua')
  expect.equality(menu_title(), ' Lua · Global Code Style · ~/xdg/config/nvim/codestyle.json ')
  expect.equality(pane_lines('options'), { '[ ] Assignment operators (=)' })
  expect.equality(pane_lines('preview'), { 'x=1', "name='codestyle'" })
end

T['the title shows the Project Code Style of the repo'] = function()
  child:write_file(child.paths.repo .. '/.codestyle.json', { version = 1 })
  child:open_buffer({ lines = { 'x=1' }, filetype = 'lua', name = child.paths.repo .. '/a.lua' })
  open_menu()
  expect.equality(menu_title(), ' Lua · Project Code Style · ~/repo/.codestyle.json ')
  expect.equality(pane_lines('languages')[1], 'Project Code Style')
end

T['opens on the language of the current buffer'] = function()
  child:open_buffer({ lines = { 'x=1' }, filetype = 'lua' })
  open_menu()
  expect.equality(child.api.nvim_get_current_win(), pane_win('options'))
  -- The fake lua has Arrangement data, so the Core adds the Arrangement Tab last.
  expect.equality(winbar_text('options'), ' Spaces   Wrapping   Other   Arrangement ')
  expect.equality(pane_lines('options'), { '[ ] Assignment operators (=)' })
end

T['<Tab> and <S-Tab> and clicks switch the Tab'] = function()
  child:open_buffer({ lines = { 'x=1' }, filetype = 'lua' })
  open_menu()
  child.type_keys('<Tab>')
  settle()
  expect.equality(pane_rows('options')[1], '▾ Function call arguments ‹Do not wrap›')
  expect.equality(pane_lines('preview'), { "print('a', 'b')" })
  child.type_keys('<S-Tab>', '<S-Tab>')
  settle()
  expect.equality(pane_rows('options')[1], '[x] Rearrange when formatting')
  child.type_keys('<S-Tab>')
  settle()
  expect.equality(pane_rows('options')[1], 'Indent [ 4 ]')

  -- A click on the first Tab of the winbar.
  local pos = child.fn.win_screenpos(pane_win('options'))
  child.api.nvim_input_mouse('left', 'press', '', 0, pos[1] - 1, pos[2] + 1)
  child.api.nvim_input_mouse('left', 'release', '', 0, pos[1] - 1, pos[2] + 1)
  settle()
  expect.equality(pane_lines('options'), { '[ ] Assignment operators (=)' })
end

T['the Preview highlights the sample, shows whitespace and sets no real filetype'] = function()
  child:open_buffer({ lines = { 'x=1' }, filetype = 'lua' })
  open_menu()
  local preview = assert(pane_win('preview'))
  local buf = child.api.nvim_win_get_buf(preview)
  local highlighter = "require('vim.treesitter.highlighter').active[...]"
  expect.equality(child.lua_get(highlighter .. ' and ' .. highlighter .. '.tree:lang()', { buf }), 'lua')
  expect.no_equality(child.lua_get('vim.bo[...].filetype', { buf }), 'lua')
  expect.equality(child.lua_get('vim.wo[...].list', { preview }), true)
  expect.equality(child.lua_get('vim.wo[...].listchars', { preview }), 'space:·,tab:→ ,trail:·')
end

T['the Preview follows the Draft'] = function()
  child:open_buffer({ lines = { 'x=1' }, filetype = 'lua' })
  open_menu()
  child.type_keys('l')
  settle()
  expect.equality(pane_lines('options'), { '[x] Assignment operators (=)' })
  expect.equality(pane_lines('languages')[5], 'Lua •1')
  expect.equality(pane_lines('preview'), { 'x = 1', "name = 'codestyle'" })
end

T['holding a value-changing key ends with the Preview on the latest Draft'] = function()
  child:open_buffer({ lines = { 'x=1' }, filetype = 'lua' })
  open_menu()
  child.lua('_G.codestyle_test_builds = 0')
  -- Nine presses in the typeahead at once, as a held key gives them.
  child.api.nvim_input(('l'):rep(9))
  settle()
  expect.equality(pane_lines('options'), { '[x] Assignment operators (=)' })
  expect.equality(pane_lines('preview'), { 'x = 1', "name = 'codestyle'" })
  -- Keys did not wait for a run each: the Preview caught up at the end.
  expect.equality(child.lua_get('_G.codestyle_test_builds') <= 2, true)
end

T['q and <Esc> close the Menu'] = function()
  for _, key in ipairs({ 'q', '<Esc>' }) do
    open_menu()
    child.type_keys(key)
    settle()
    expect.equality(float_filetypes(), {})
    expect.equality(pane_win('options'), nil)
  end
  expect.equality(child:notices(), {})
end

T['g? lists the keys'] = function()
  open_menu()
  child.type_keys('g?')
  settle()
  local help = pane_lines('help')
  expect.equality(vim.list_contains(help, 'q        close'), true)
  expect.equality(vim.list_contains(help, '<Tab>    next Tab'), true)
  expect.equality(vim.list_contains(help, 'l        next value'), true)
  child.type_keys('q')
  settle()
  expect.equality(pane_win('help'), nil)
  expect.equality(child.api.nvim_get_current_win(), pane_win('options'))
end

T['a Preview run that raises keeps the last good output and shows the marker'] = function()
  child:open_buffer({ lines = { 'x=1' }, filetype = 'broken' })
  open_menu()
  expect.equality(pane_lines('preview'), { 'x = 1' })
  expect.equality(winbar_text('preview'), ' Preview')

  child.type_keys('l')
  settle()
  expect.equality(pane_lines('preview'), { 'x = 1' })
  expect.equality(winbar_text('preview'), '⚠ broken: formatter error')
  local notices = child:notices()
  expect.equality(#notices, 1)
  expect.equality(notices[1].level, H.levels.ERROR)
  expect.equality(notices[1].message:find('the fake broken plugin raises on purpose', 1, true) ~= nil, true)

  child.type_keys('l')
  settle()
  expect.equality(winbar_text('preview'), ' Preview')
end

T['a broken Code Style file does not open the Menu'] = function()
  child:write_global('{ "version": 1,')
  open_menu()
  expect.equality(pane_win('options'), nil)
  local notices = child:notices()
  expect.equality(#notices, 1)
  expect.equality(notices[1].level, H.levels.ERROR)
end

T['screenshots'] = MiniTest.new_set()

---@param name string
local function screenshot(name)
  M.screenshot(child, name)
end

T['screenshots']['the Menu just opened'] = function()
  child:write_global({ version = 1, languages = { lua = { spaces = { around_assignment = true } }, gone = { a = 1 } } })
  child:open_buffer({ lines = { 'x=1' }, filetype = 'lua' })
  open_menu()
  screenshot('menu-opened')
end

T['screenshots']['the failure marker'] = function()
  child:open_buffer({ lines = { 'x=1' }, filetype = 'broken' })
  open_menu()
  child.type_keys('l')
  screenshot('menu-failure-marker')
end

T['screenshots']['a narrow window'] = function()
  child:open_buffer({ lines = { 'x=1' }, filetype = 'lua' })
  open_menu()
  child.o.columns = 50
  screenshot('menu-narrow')
end

return T
