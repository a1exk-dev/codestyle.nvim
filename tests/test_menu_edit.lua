-- Editing Options in the Menu (ADR-0004, ADR-0003, ADR-0006, ADR-0018): keys
-- and clicks in a child Neovim, read back from the panes, the notices, the
-- `vim.ui` calls (the user's picker) and the saved Code Style file.

local H = dofile('tests/helpers.lua')
local M = dofile('tests/menu_helpers.lua')
local expect = MiniTest.expect

local child = H.new_child()

local T = MiniTest.new_set({
  hooks = {
    pre_case = function()
      M.setup(child, { 'codestyle-lua.nvim' })
    end,
    post_case = function()
      child:teardown()
    end,
  },
})

--- Switches the open Menu to the Tab with this name.
---@param tab string
local function to_tab(tab)
  for _ = 1, 3 do
    local winbar = child.lua_get('vim.wo[...].winbar', { M.pane_win(child, 'options') })
    if winbar:find('TabLineSel#%%%d+@[^@]*@ ' .. tab .. ' ') then
      return
    end
    child.type_keys('<Tab>')
    M.settle(child)
  end
  error('no Tab ' .. tab)
end

--- Opens the Menu on the fake lua's Tab with this name.
---@param tab string
local function open_lua(tab)
  child:open_buffer({ lines = { 'x=1' }, filetype = 'lua' })
  M.open_menu(child)
  to_tab(tab)
end

---@param keys string|string[]
local function keys(keys)
  child.type_keys(keys)
  M.settle(child)
end

local function rows()
  return M.pane_rows(child, 'options')
end

--- The row of the Options pane that holds the text.
---@param text string
local function row(text)
  for _, line in ipairs(rows()) do
    if line:find(text, 1, true) then
      return line
    end
  end
end

---@param text string
local function on(text)
  M.cursor_on(child, 'options', text)
end

--- The Global file as saved, after `<C-s>`.
local function saved()
  keys('<C-s>')
  local path = child.paths.config .. '/codestyle.json'
  return vim.json.decode(table.concat(vim.fn.readfile(path), '\n'))
end

T['boolean'] = MiniTest.new_set()

T['boolean']['<Space>, <CR>, l, h toggle and x resets'] = function()
  open_lua('Other')
  on('Remove semicolons')
  keys('<Space>')
  expect.equality(row('Remove semicolons'), '[x] Remove semicolons')
  keys('<CR>')
  expect.equality(row('Remove semicolons'), '[ ] Remove semicolons')
  keys('l')
  expect.equality(row('Remove semicolons'), '[x] Remove semicolons')
  keys('x')
  expect.equality(row('Remove semicolons'), '[ ] Remove semicolons')
  keys('h')
  expect.equality(row('Remove semicolons'), '[x] Remove semicolons')
end

T['boolean']['a click on the checkbox toggles, a click on the label only moves the cursor'] = function()
  open_lua('Other')
  M.click(child, 'left', 'options', '[ ] Remove semicolons')
  expect.equality(row('Remove semicolons'), '[x] Remove semicolons')
  M.click(child, 'left', 'options', 'Use double quotes')
  expect.equality(row('Use double quotes'), '[ ] Use double quotes ⚑')
  expect.equality(child.api.nvim_get_current_line():find('Use double quotes', 1, true) ~= nil, true)
end

T['boolean']['a right-click on the checkbox toggles without a popup menu'] = function()
  open_lua('Other')
  M.click(child, 'right', 'options', '[ ] Remove semicolons')
  expect.equality(row('Remove semicolons'), '[x] Remove semicolons')
  expect.equality(child.fn.pumvisible(), 0)
  M.click(child, 'right', 'options', 'Remove semicolons')
  expect.equality(row('Remove semicolons'), '[x] Remove semicolons')
end

T['integer'] = MiniTest.new_set()

T['integer']['<CR> asks with the range, l/h step within it, x resets'] = function()
  open_lua('Other')
  on('Indent')
  M.answer(child, { '2' })
  keys('<CR>')
  expect.equality(row('Indent'), 'Indent [ 2 ]')
  expect.equality(M.ui_calls(child)[1], { kind = 'input', prompt = 'Indent [0–32]: ', default = '4' })
  keys({ 'h', 'h', 'h' })
  expect.equality(row('Indent'), 'Indent [ 0 ]')
  keys('l')
  expect.equality(row('Indent'), 'Indent [ 1 ]')
  keys('x')
  expect.equality(row('Indent'), 'Indent [ 4 ]')
end

T['integer']['an input out of range or not a number is refused with an ERROR'] = function()
  open_lua('Other')
  on('Indent')
  M.answer(child, { '99', 'wide' })
  keys('<CR>')
  keys('<CR>')
  expect.equality(row('Indent'), 'Indent [ 4 ]')
  local notices = child:notices()
  expect.equality(#notices, 2)
  expect.equality(notices[1], { level = H.levels.ERROR, message = 'codestyle: Indent: 99 is out of range 0–32' })
  expect.equality(notices[2].level, H.levels.ERROR)
end

T['integer']['a click on the value asks; a right-click only moves the cursor'] = function()
  open_lua('Other')
  M.click(child, 'right', 'options', '[ 4 ]')
  expect.equality(M.ui_calls(child), {})
  M.answer(child, { '8' })
  M.click(child, 'left', 'options', '[ 4 ]')
  expect.equality(row('Indent'), 'Indent [ 8 ]')
end

T['integer']['an inherited value shows Default: 120, and an empty input inherits again'] = function()
  open_lua('Wrapping')
  expect.equality(row('Hard wrap at'), 'Hard wrap at Default: 120')
  on('Hard wrap at')
  M.answer(child, { '100' })
  keys('<CR>')
  expect.equality(row('Hard wrap at'), 'Hard wrap at [ 100 ]')
  expect.equality(M.ui_calls(child)[1].prompt, 'Hard wrap at [1–1000] (empty: inherit General): ')
  M.answer(child, { '' })
  keys('<CR>')
  expect.equality(row('Hard wrap at'), 'Hard wrap at Default: 120')
  expect.equality(saved().languages, nil)
end

T['choice'] = MiniTest.new_set()

T['choice']['<Space> and l cycle, h cycles back, <CR> picks with vim.ui.select'] = function()
  open_lua('Wrapping')
  on('Function call arguments')
  keys('<Space>')
  expect.equality(row('Function call arguments'), '▾ Function call arguments ‹Wrap if long›')
  keys('l')
  expect.equality(row('Function call arguments'), '▾ Function call arguments ‹Chop down if long›')
  keys('l')
  expect.equality(row('Function call arguments'), '▾ Function call arguments ‹Do not wrap›')
  keys('h')
  expect.equality(row('Function call arguments'), '▾ Function call arguments ‹Chop down if long›')
  M.answer(child, { 'Wrap if long' })
  keys('<CR>')
  expect.equality(row('Function call arguments'), '▾ Function call arguments ‹Wrap if long›')
  expect.equality(M.ui_calls(child)[1], {
    kind = 'select',
    prompt = 'Function call arguments',
    items = { '  Do not wrap', '  Wrap if long', '● Chop down if long' },
  })
end

T['choice']['a click opens the picker, a right-click cycles'] = function()
  open_lua('Wrapping')
  M.click(child, 'right', 'options', '‹Do not wrap›')
  expect.equality(row('Function call arguments'), '▾ Function call arguments ‹Wrap if long›')
  M.answer(child, { 'Do not wrap' })
  M.click(child, 'left', 'options', '‹Wrap if long›')
  expect.equality(row('Function call arguments'), '▾ Function call arguments ‹Do not wrap›')
  expect.equality(#M.ui_calls(child), 1)
end

T['string'] = MiniTest.new_set()

T['string']['<CR> and a click edit with vim.ui.input; <Space> and l do nothing'] = function()
  open_lua('Other')
  on('TODO marker')
  keys({ '<Space>', 'l' })
  expect.equality(M.ui_calls(child), {})
  M.answer(child, { 'FIXME' })
  keys('<CR>')
  expect.equality(row('TODO marker'), 'TODO marker "FIXME"')
  expect.equality(M.ui_calls(child)[1], { kind = 'input', prompt = 'TODO marker: ', default = 'TODO' })
  M.answer(child, { 'XXX' })
  M.click(child, 'left', 'options', '"FIXME"')
  expect.equality(row('TODO marker'), 'TODO marker "XXX"')
  M.answer(child, { vim.NIL })
  keys('<CR>')
  expect.equality(row('TODO marker'), 'TODO marker "XXX"')
end

T['list'] = MiniTest.new_set()

T['list']['<CR> opens a float with one item per line, <CR> applies'] = function()
  open_lua('Other')
  on('Known globals')
  keys('<CR>')
  expect.equality(M.pane_lines(child, 'list'), { 'vim' })
  child.type_keys('o', 'MiniTest', '<Esc>', 'o', '<Esc>')
  keys('<CR>')
  expect.equality(M.pane_win(child, 'list'), nil)
  expect.equality(row('Known globals'), 'Known globals [vim, MiniTest]')
  expect.equality(child.api.nvim_get_current_win(), M.pane_win(child, 'options'))
end

T['list']['a bad item is refused and the float stays; q cancels'] = function()
  open_lua('Wrapping')
  on('Visual guides')
  keys('<CR>')
  child.type_keys('i', '80', '<Esc>', 'o', 'wide', '<Esc>')
  keys('<CR>')
  expect.equality(M.pane_win(child, 'list') ~= nil, true)
  local notices = child:notices()
  expect.equality(notices[#notices].level, H.levels.ERROR)
  expect.equality(notices[#notices].message:find('Visual guides: item 2', 1, true) ~= nil, true)
  keys('q')
  expect.equality(M.pane_win(child, 'list'), nil)
  expect.equality(row('Visual guides'), 'Visual guides []')
end

T['order'] = MiniTest.new_set()

T['order']['<CR> opens a float where J/K move, <CR> applies, q cancels'] = function()
  open_lua('Other')
  on('Order of module members')
  keys('<CR>')
  expect.equality(M.pane_lines(child, 'order'), { 'fields', 'methods', 'metamethods' })
  keys({ 'J', 'J' })
  expect.equality(M.pane_lines(child, 'order'), { 'methods', 'metamethods', 'fields' })
  keys('K')
  expect.equality(M.pane_lines(child, 'order'), { 'methods', 'fields', 'metamethods' })
  keys('<CR>')
  expect.equality(row('Order of module members'), 'Order of module members methods › fields › metamethods')

  keys('<CR>')
  keys({ 'J', 'q' })
  expect.equality(M.pane_win(child, 'order'), nil)
  expect.equality(row('Order of module members'), 'Order of module members methods › fields › metamethods')
  expect.equality(saved().languages.lua.members.order, { 'methods', 'fields', 'metamethods' })
end

T['order']['<Space> and a right-click do nothing, a click opens the float'] = function()
  open_lua('Other')
  on('Order of module members')
  keys('<Space>')
  M.click(child, 'right', 'options', 'fields › methods')
  expect.equality(M.pane_win(child, 'order'), nil)
  M.click(child, 'left', 'options', 'fields › methods')
  expect.equality(M.pane_win(child, 'order') ~= nil, true)
end

T['dimmed Options'] = MiniTest.new_set()

T['dimmed Options']['markers.* are dimmed while markers are off, and their edits are refused'] = function()
  child:write_global({ version = 1, languages = { general = { markers = { enabled = false } } } })
  M.open_menu(child)
  keys('<Tab>')
  expect.equality(rows(), {
    'Do not format []',
    '▾ Formatter markers [ ]',
    'Formatter off "@formatter:off"',
    'Formatter on "@formatter:on"',
    '[ ] Enable regular expressions in formatter markers',
  })
  expect.equality(M.groups_at(child, 'options', 'Formatter off'), { 'Comment' })
  on('Enable regular expressions')
  keys('<Space>')
  on('Formatter off')
  keys('<CR>')
  expect.equality(row('Enable regular'), '[ ] Enable regular expressions in formatter markers')
  expect.equality(M.ui_calls(child), {})
  local message = 'codestyle: "Formatter off" is inactive: it needs '
    .. '"Turn formatter on/off with markers in code comments" on'
  expect.equality(child:notices()[2], { level = H.levels.WARN, message = message })

  on('Formatter markers')
  keys('<Space>')
  expect.equality(M.groups_at(child, 'options', 'Formatter off'), {})
end

T['dimmed Options']['a dependency on a choice names the choice'] = function()
  open_lua('Wrapping')
  on('Align when multiline')
  keys('<Space>')
  expect.equality(child:notices(), {
    {
      level = H.levels.WARN,
      message = 'codestyle: "Align when multiline" is inactive: it needs "Function call arguments" '
        .. 'set to another value than "Do not wrap"',
    },
  })
  on('Function call arguments')
  keys('l')
  on('Align when multiline')
  keys('<Space>')
  expect.equality(row('Align when multiline'), '[x] Align when multiline')
end

T['a regex marker tag must be a valid Vim regex'] = function()
  child:write_global({ version = 1, languages = { general = { markers = { regex = true } } } })
  M.open_menu(child)
  keys('<Tab>')
  on('Formatter off')
  M.answer(child, { 'off\\(', 'off\\d' })
  keys('<CR>')
  expect.equality(row('Formatter off'), 'Formatter off "@formatter:off"')
  expect.equality(child:notices()[1].level, H.levels.ERROR)
  keys('<CR>')
  expect.equality(row('Formatter off'), 'Formatter off "off\\d"')
end

T['changed values are highlighted, •N counts, Flagged Options are marked'] = function()
  open_lua('Other')
  expect.equality(row('Use double quotes'), '[ ] Use double quotes ⚑')
  expect.equality(M.groups_at(child, 'options', '⚑'), { 'DiagnosticWarn' })
  on('Indent')
  keys('l')
  expect.equality(M.groups_at(child, 'options', 'Indent'), { 'CodestyleChanged' })
  expect.equality(M.pane_lines(child, 'languages')[4], 'Lua •1')
  on('Remove semicolons')
  keys('<Space>')
  expect.equality(M.pane_lines(child, 'languages')[4], 'Lua •2')
  keys('<Space>')
  expect.equality(M.groups_at(child, 'options', 'Remove semicolons'), {})
  expect.equality(M.pane_lines(child, 'languages')[4], 'Lua •1')
end

T['Groups fold with za, <CR> and a click on the arrow'] = function()
  open_lua('Wrapping')
  on('Function call arguments')
  keys('za')
  expect.equality(rows(), { '▸ Function call arguments ‹Do not wrap›', 'Visual guides []' })
  M.click(child, 'left', 'options', '▸')
  expect.equality(#rows(), 4)
end

T['f filters every Tab with breadcrumbs, the Preview follows, F clears'] = function()
  open_lua('Spaces')
  M.answer(child, { 'wrap' })
  keys('f')
  expect.equality(rows(), { 'Wrapping › Function call arguments › Hard wrap at Default: 120' })
  expect.equality(M.winbar_text(child, 'options'), ' Filter: wrap  F clears')
  expect.equality(M.pane_lines(child, 'preview'), { "print('a', 'b')" })

  M.answer(child, { 'O' })
  keys('f')
  on('Assignment operators')
  expect.equality(M.pane_lines(child, 'preview'), { 'x=1', "name='codestyle'" })
  on('Order of module members')
  expect.equality(M.pane_lines(child, 'preview'), { "x='a';" })
  keys('<Space>')

  keys('F')
  expect.equality(rows(), { '[ ] Assignment operators (=)' })
  expect.equality(M.pane_lines(child, 'preview'), { 'x=1', "name='codestyle'" })
end

T['/ finds Option labels'] = function()
  open_lua('Other')
  child.type_keys('/', 'Known', '<CR>')
  expect.equality(child.api.nvim_get_current_line():find('Known globals', 1, true) ~= nil, true)
end

T['changed Preview lines stay marked until the output changes'] = function()
  open_lua('Other')
  local function marked()
    local buf = child.api.nvim_win_get_buf(M.pane_win(child, 'preview'))
    return child.lua(
      [[
        local rows = {}
        for _, mark in ipairs(vim.api.nvim_buf_get_extmarks(..., -1, 0, -1, { details = true })) do
          if mark[4].line_hl_group == 'CodestylePreviewChanged' then
            table.insert(rows, mark[2])
          end
        end
        return rows
      ]],
      { buf }
    )
  end
  expect.equality(marked(), {})
  on('Remove semicolons')
  keys('<Space>')
  expect.equality(M.pane_lines(child, 'preview'), { "x='a'" })
  expect.equality(marked(), { 0 })
  -- An Option that this sample does not show: the output and the mark stay.
  on('TODO marker')
  M.answer(child, { 'XXX' })
  keys('<CR>')
  expect.equality(marked(), { 0 })
  on('Remove semicolons')
  keys('<Space>')
  expect.equality(marked(), { 0 })
  expect.equality(M.pane_lines(child, 'preview'), { "x='a';" })
end

T['u and <C-r> undo and redo the Draft'] = function()
  open_lua('Other')
  on('Indent')
  keys({ 'l', 'l' })
  expect.equality(row('Indent'), 'Indent [ 6 ]')
  keys('u')
  expect.equality(row('Indent'), 'Indent [ 5 ]')
  keys({ 'u', 'u' })
  expect.equality(row('Indent'), 'Indent [ 4 ]')
  keys('<C-r>')
  expect.equality(row('Indent'), 'Indent [ 5 ]')
end

T['the save key writes the file'] = function()
  open_lua('Other')
  on('Indent')
  keys('l')
  expect.equality(saved(), { version = 1, languages = { lua = { indent = { size = 5 } } } })
  expect.equality(child:notices(), {
    { level = H.levels.INFO, message = 'codestyle: saved ~/xdg/config/nvim/codestyle.json' },
  })
  keys('q')
  expect.equality(M.pane_win(child, 'options'), nil)
  expect.equality(M.ui_calls(child), {})
end

T['closing with changes asks Save / Discard / Cancel'] = function()
  open_lua('Other')
  on('Indent')
  keys('l')
  M.answer(child, { 'Cancel' })
  keys('q')
  expect.equality(M.pane_win(child, 'options') ~= nil, true)
  local ask = M.ui_calls(child)[1]
  expect.equality(ask.items, { 'Save', 'Discard', 'Cancel' })
  expect.equality(ask.prompt, 'The Draft has unsaved changes. Save them to ~/xdg/config/nvim/codestyle.json?')

  M.answer(child, { 'Discard' })
  keys('<Esc>')
  expect.equality(M.pane_win(child, 'options'), nil)
  expect.equality(vim.fn.filereadable(child.paths.config .. '/codestyle.json'), 0)

  M.open_menu(child)
  to_tab('Other')
  on('Indent')
  keys('h')
  M.answer(child, { 'Save' })
  keys('q')
  expect.equality(M.pane_win(child, 'options'), nil)
  local path = child.paths.config .. '/codestyle.json'
  expect.equality(vim.json.decode(table.concat(vim.fn.readfile(path), '\n')).languages.lua.indent.size, 3)
end

T['a Menu window closed another way asks too, and Cancel opens it again'] = function()
  open_lua('Other')
  on('Indent')
  keys('l')
  M.answer(child, { 'Cancel' })
  child.cmd('close')
  M.settle(child)
  expect.equality(M.pane_win(child, 'options') ~= nil, true)
  expect.equality(row('Indent'), 'Indent [ 5 ]')
end

-- A wider screen than the shell's screenshots, so that every value control shows.
T['screenshots'] = MiniTest.new_set({
  hooks = {
    pre_case = function()
      child.o.lines, child.o.columns = 30, 120
    end,
  },
})

T['screenshots']['the value controls'] = function()
  child:write_global({
    version = 1,
    languages = { lua = { indent = { size = 2 }, names = { globals = { 'vim', 'MiniTest' } } } },
  })
  open_lua('Other')
  M.screenshot(child, 'menu-controls')
  keys('<S-Tab>')
  M.screenshot(child, 'menu-controls-group')
end

T['screenshots']['the filter'] = function()
  open_lua('Spaces')
  M.answer(child, { 'a' })
  keys('f')
  M.screenshot(child, 'menu-filter')
end

return T
