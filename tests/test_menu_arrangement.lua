-- The Arrangement Tab of the Menu (ADR-0012, ADR-0011): its rows, keys and
-- floats in a child Neovim, read back from the panes, the notices, the Draft
-- (through undo and the saved file) and the Preview. The fake lua has the
-- rule rows; the fake c has the sort panel.

local H = dofile('tests/helpers.lua')
local M = dofile('tests/menu_helpers.lua')
local expect = MiniTest.expect

local child = H.new_child()

local T = MiniTest.new_set({
  hooks = {
    pre_case = function()
      M.setup(child, { 'codestyle-lua.nvim', 'codestyle-c.nvim' })
    end,
    post_case = function()
      child:teardown()
    end,
  },
})

---@param keys string|string[]
local function keys(keys)
  child.type_keys(keys)
  M.settle(child)
end

--- Opens the Menu on the Arrangement Tab of a language.
---@param filetype 'lua'|'c'
local function open_tab(filetype)
  child:open_buffer({ lines = { '' }, filetype = filetype })
  M.open_menu(child)
  keys('<S-Tab>')
end

local function rows()
  return M.pane_rows(child, 'options')
end

---@param text string
local function on(text)
  M.cursor_on(child, 'options', text)
end

---@param arrangement table the stored Arrangement of the fake lua
local function stored(arrangement)
  child:write_global({ version = 1, languages = { lua = { arrangement = arrangement } } })
end

--- The Global file as saved, after `<C-s>`.
local function saved()
  keys('<C-s>')
  local path = child.paths.config .. '/codestyle.json'
  return vim.json.decode(table.concat(vim.fn.readfile(path), '\n'))
end

--- The messages of the notices since the case began.
local function messages()
  return vim.tbl_map(function(notice)
    return notice.message
  end, child:notices())
end

--- The default Arrangement of the fake lua, with changes.
---@param changes? table
local function lua_default(changes)
  return vim.tbl_extend('force', {
    enabled = true,
    aliases = vim.empty_dict(),
    keep_together = { { kind = 'getters_setters', order = 'keep' } },
    slots = { { { is = { 'field' } } }, { { is = { 'function' } } }, { { is = { 'method' } } } },
  }, changes or {})
end

T['rows'] = MiniTest.new_set()

T['rows']['Rearrange when formatting, Keep-Together rows, rule rows with Slot numbers and │, folded aliases'] = function()
  stored(lua_default({
    aliases = { hidden = { { is = { 'private' } }, { is = { 'metamethod' } } } },
    slots = {
      { { is = { 'field' }, is_not = { 'private' } }, { name = 'get.*', order = 'by_name' } },
      { { is = { 'method' }, alias = 'hidden' } },
    },
  }))
  open_tab('lua')

  expect.equality(rows(), {
    '[x] Rearrange when formatting',
    '',
    'Keep together',
    '[ ] Dependent methods ‹Depth-first›',
    '[x] Getters and setters',
    '[ ] Overridden methods ‹Keep order›',
    '',
    'Slots',
    '1 field !private',
    '│ name /get.*/ by name',
    '2 method alias hidden',
    '',
    '▸ Aliases (1)',
  })
  on('Aliases')
  keys('<CR>')
  expect.equality(rows()[14], 'hidden private | metamethod')
  keys('za')
  expect.equality(#rows(), 13)
end

T['rows']['each edit is one undo step; the Tab and •N show a changed Arrangement as one item'] = function()
  open_tab('lua')
  on('Rearrange when formatting')
  keys('<Space>')
  expect.equality(rows()[1], '[ ] Rearrange when formatting')
  expect.equality(M.pane_rows(child, 'languages')[5], 'Lua •1')
  expect.equality(M.winbar_text(child, 'options'), ' Spaces   Wrapping   Other   Arrangement • ')
  on('Overridden methods')
  keys('l')
  expect.equality(rows()[6], '[x] Overridden methods ‹By name›')
  keys('u')
  expect.equality(rows()[6], '[ ] Overridden methods ‹Keep order›')
  keys('u')
  expect.equality(rows()[1], '[x] Rearrange when formatting')
  expect.equality(M.pane_rows(child, 'languages')[5], 'Lua')
  keys('<C-r>')
  expect.equality(saved().languages.lua.arrangement, lua_default({ enabled = false, aliases = {} }))
end

T['rows']['an invalid stored Arrangement shows a warning row and the default, stays until edited or reset'] = function()
  stored({ slots = { { { is = { 'nonsense' } } } } })
  open_tab('lua')

  expect.equality(vim.list_slice(rows(), 1, 3), {
    '⚠ arrangement.slots[1][1].is: unknown token "nonsense"; the whole default Arrangement is used',
    'The rows show the default. An edit or X replaces the stored value.',
    '[x] Rearrange when formatting',
  })
  expect.equality(rows()[11], '1 field')
  -- A save keeps the stored value.
  expect.equality(saved().languages.lua.arrangement, { slots = { { { is = { 'nonsense' } } } } })

  -- The first edit replaces it with the default and the edit; undo brings it back.
  on('Rearrange when formatting')
  keys('<Space>')
  expect.equality(rows()[1], '[ ] Rearrange when formatting')
  keys('u')
  expect.equality(vim.startswith(rows()[1], '⚠ arrangement.slots'), true)
  keys('<C-r>')
  expect.equality(saved().languages.lua.arrangement, lua_default({ enabled = false, aliases = {} }))
  keys('X')
  expect.equality(rows()[1], '[x] Rearrange when formatting')
  expect.equality(saved().languages, nil)
end

T['rows']['x resets Rearrange when formatting and a Keep-Together Rule; on a rule it only says so; X resets all'] = function()
  stored(lua_default({ enabled = false, keep_together = { { kind = 'dependent_methods', order = 'breadth_first' } } }))
  open_tab('lua')
  on('Rearrange when formatting')
  keys('x')
  expect.equality(rows()[1], '[x] Rearrange when formatting')
  on('Getters and setters')
  keys('x')
  expect.equality(rows()[5], '[x] Getters and setters')
  on('2  function')
  keys('x')
  expect.equality(messages(), {
    'codestyle: a rule has no default of its own; X resets the whole Arrangement',
  })
  keys('X')
  expect.equality(rows()[4], '[ ] Dependent methods ‹Depth-first›')
  keys('u')
  expect.equality(rows()[4], '[x] Dependent methods ‹Breadth-first›')
end

--- In the open picker, toggles each token (types it, then `<Tab>`), then confirms.
---@param tokens string[]
local function pick(tokens)
  child.lua('vim.wait(50)')
  for _, token in ipairs(tokens) do
    keys(token)
    child.lua('vim.wait(50)')
    keys({ '<Tab>', '<C-w>' })
  end
  keys('<CR>')
  child.lua('vim.wait(50)')
end

--- The rows of the rule float with each run of blanks as one space.
local function float_rows()
  return M.pane_rows(child, 'rule')
end

--- Opens the rule float's row of a part and edits it with `<CR>`.
---@param part string
local function edit_part(part)
  M.cursor_on(child, 'rule', part)
  keys('<CR>')
end

---@param slots table
local function lua_slots(slots)
  stored(lua_default({ slots = slots }))
end

T['rows']['f finds the fixed labels of the Tab, not the Slot rows'] = function()
  open_tab('lua')
  M.answer(child, { 'method' })
  keys('f')
  expect.equality(rows(), {
    'Arrangement › Keep together › [ ] Dependent methods ‹Depth-first›',
    'Arrangement › Keep together › [ ] Overridden methods ‹Keep order›',
  })
  keys('<Space>')
  expect.equality(rows()[1], 'Arrangement › Keep together › [x] Dependent methods ‹Depth-first›')
end

T['rule float'] = MiniTest.new_set()

T['rule float']['o opens it for a new Slot below; closed with no condition, the rule is dropped with no undo step'] = function()
  open_tab('lua')
  on('1  field')
  keys('o')
  expect.equality(float_rows(), { 'Is', 'Is not', 'Name', 'Namespace', 'Alias', 'Order Keep order' })
  -- An Order alone is no condition.
  M.answer(child, { 'By name' })
  edit_part('Order')
  keys('q')
  expect.equality(M.pane_win(child, 'rule'), nil)
  expect.equality(rows()[10], '2 function')
  expect.equality(M.pane_win(child, 'options') ~= nil, true)
  keys('u')
  expect.equality(rows()[9], '1 field')
  expect.equality(messages(), {})
  expect.equality(saved().languages, nil)
end

T['rule float']['the first condition adds the rule; each confirmed edit is one undo step'] = function()
  open_tab('lua')
  on('1  field')
  keys('o')
  edit_part('Is')
  pick({ 'method' })
  expect.equality(float_rows()[1], 'Is method')
  edit_part('Is not')
  pick({ 'private' })
  M.answer(child, { 'By name' })
  edit_part('Order')
  keys('q')
  expect.equality(vim.list_slice(rows(), 9, 12), { '1 field', '2 method !private by name', '3 function', '4 method' })
  keys('u')
  expect.equality(rows()[10], '2 method !private')
  keys('u')
  expect.equality(rows()[10], '2 method')
  keys('u')
  expect.equality(rows()[10], '2 function')
end

T['rule float']['a adds a rule to the Slot under the cursor; <CR> edits a rule'] = function()
  open_tab('lua')
  on('2  function')
  keys('a')
  M.answer(child, { 'get.*' })
  edit_part('Name')
  keys('q')
  expect.equality(vim.list_slice(rows(), 10, 12), { '2 function', '│ name /get.*/', '3 method' })
  on('name /get')
  keys('<CR>')
  expect.equality(float_rows()[3], 'Name /get.*/')
  M.cursor_on(child, 'rule', 'Name')
  keys('x')
  expect.equality(float_rows()[3], 'Name')
  edit_part('Is')
  pick({ 'function' })
  keys('q')
  expect.equality(rows()[11], '│ function')
end

T['rule float']["Is and Is not leave out each other's tokens; exclusive tokens are refused and the picker opens again"] = function()
  open_tab('lua')
  on('3  method')
  keys('<CR>')
  edit_part('Is not')
  child.lua('vim.wait(50)')
  local shown = child.lua([[
      local picker = Snacks.picker.get()[1]
      return vim.tbl_map(function(item) return item.text end, picker:items())
    ]])
  expect.equality(shown, { 'field', 'function', 'private', 'metamethod', 'overridden' })
  -- The first <Esc> leaves Insert mode in the picker's input, the second closes it.
  keys({ '<Esc>', '<Esc>' })
  child.lua('vim.wait(50)')
  edit_part('Is')
  pick({ 'field' })
  expect.equality(messages(), { 'codestyle: Is: field, method cannot be together in one rule' })
  -- The picker is open again with that set; the user takes field out.
  local selected = child.lua([[
      return vim.tbl_map(function(item) return item.text end, Snacks.picker.get()[1]:selected({ fallback = false }))
    ]])
  expect.equality(selected, { 'field', 'method' })
  pick({ 'method' })
  expect.equality(float_rows()[1], 'Is field')
  keys('q')
  expect.equality(rows()[11], '3 field')
end

T['rule float']['a bad regex is refused with its error'] = function()
  open_tab('lua')
  on('1  field')
  keys('<CR>')
  M.answer(child, { 'get\\(' })
  edit_part('Namespace')
  expect.equality(float_rows()[4], 'Namespace')
  expect.equality(messages(), {
    'codestyle: Namespace: "get\\(" is not a valid Vim regex: E54: Unmatched \\(',
  })
  keys('q')
  expect.equality(saved().languages, nil)
end

T['moves'] = MiniTest.new_set()

T['moves']['J/K move a rule and join the next Slot past its edge; gJ/gK move the Slot; dd deletes'] = function()
  lua_slots({ { { is = { 'field' } }, { is = { 'function' } } }, { { is = { 'method' } } } })
  open_tab('lua')
  local function slots()
    return vim.list_slice(rows(), 9, 11)
  end
  on('│  function')
  keys('K')
  expect.equality(slots(), { '1 function', '│ field', '2 method' })
  keys('J')
  keys('J')
  expect.equality(slots(), { '1 field', '2 function', '│ method' })
  -- The cursor followed the rule.
  expect.equality(child.api.nvim_get_current_line(), '  2  function')
  keys('J')
  expect.equality(slots(), { '1 field', '2 method', '│ function' })
  keys('gK')
  expect.equality(slots(), { '1 method', '│ function', '2 field' })
  keys('gJ')
  expect.equality(slots(), { '1 field', '2 method', '│ function' })
  keys('dd')
  expect.equality(slots(), { '1 field', '2 method', '' })
  keys('u')
  expect.equality(slots(), { '1 field', '2 method', '│ function' })
end

T['aliases'] = MiniTest.new_set()

T['aliases']['o adds one with a unique name, r renames it in every rule, dd is refused while a rule uses it'] = function()
  stored(lua_default({
    aliases = { hidden = { { is = { 'private' } } } },
    slots = {
      { { is = { 'field' }, alias = 'hidden' } },
      { { is = { 'method' }, alias = 'hidden' } },
      { { is = { 'function' } } },
    },
  }))
  open_tab('lua')
  on('Aliases')
  keys('<CR>')
  on('  hidden')
  M.answer(child, { 'hidden' })
  keys('o')
  expect.equality(messages(), { 'codestyle: an alias "hidden" exists already; an alias needs a name of its own' })
  M.answer(child, { 'magic' })
  keys('o')
  edit_part('Is')
  pick({ 'metamethod' })
  keys('q')
  expect.equality(vim.list_slice(rows(), 14, 15), { 'hidden private', 'magic metamethod' })

  on('  hidden')
  keys('dd')
  expect.equality(messages()[2], 'codestyle: the alias "hidden" is used by the rules of Slot 1, 2; change them first')
  M.answer(child, { 'secret' })
  keys('r')
  expect.equality(vim.list_slice(rows(), 9, 11), { '1 field alias secret', '2 method alias secret', '3 function' })
  on('magic')
  keys('dd')
  expect.equality(rows()[13], '▾ Aliases (1)')
end

T['aliases']["<CR> opens the alias's rules with the same keys"] = function()
  stored(lua_default({ aliases = { hidden = { { is = { 'private' } }, { is = { 'metamethod' } } } } }))
  open_tab('lua')
  on('Aliases')
  keys('<CR>')
  on('  hidden')
  keys('<CR>')
  expect.equality(M.pane_lines(child, 'alias'), { 'private', 'metamethod' })
  keys('J')
  expect.equality(M.pane_lines(child, 'alias'), { 'metamethod', 'private' })
  -- The cursor followed the rule.
  keys('<CR>')
  -- An alias's rule has no Alias and no Order.
  expect.equality(float_rows(), { 'Is private', 'Is not', 'Name', 'Namespace' })
  keys('q')
  expect.equality(M.pane_win(child, 'alias') ~= nil, true)
  keys('dd')
  expect.equality(M.pane_lines(child, 'alias'), { 'metamethod' })
  keys('dd')
  expect.equality(
    messages(),
    { 'codestyle: the alias "hidden" needs a rule; dd on its row in the Tab deletes the alias' }
  )
  keys('q')
  expect.equality(rows()[14], 'hidden metamethod')
end

T['Preview'] = MiniTest.new_set()

--- The Slot texts of the Preview's lines, and the rows of the highlighted
--- entries: `{ [row] = slot text }`, `{ rows }`, both 1-based.
local function preview_marks()
  return child.lua([[
    local buf = vim.fn.bufnr('codestyle://preview')
    local ns = vim.api.nvim_get_namespaces()['codestyle.preview.slots']
    local slots, highlighted = {}, {}
    for _, mark in ipairs(vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, { details = true })) do
      local details = mark[4]
      if details.virt_text then
        slots[tostring(mark[2] + 1)] = vim.trim(details.virt_text[1][1])
      elseif details.hl_group == 'CodestyleRuleEntry' then
        table.insert(highlighted, mark[2] + 1)
      end
    end
    return { slots, highlighted }
  ]])
end

T['Preview']["shows the sample rearranged then formatted, each entry's Slot, and the entries of the rule under the cursor"] = function()
  open_tab('lua')
  -- Formatted with the defaults: no spaces around `=`.
  expect.equality(M.pane_lines(child, 'preview'), {
    'local M={}',
    '',
    'M.x=1',
    'M._y=2',
    '',
    'function M.f() end',
    '',
    'function M:m() end',
    '',
    'return M',
  })
  on('1  field')
  expect.equality(preview_marks(), { { ['3'] = '1', ['4'] = '1', ['6'] = '2', ['8'] = '3' }, { 3, 4 } })
  on('3  method')
  expect.equality(preview_marks()[2], { 8 })
  keys('dd')
  M.settle(child)
  -- No rule takes the method now: it goes last, with `–`.
  expect.equality(preview_marks()[1], { ['3'] = '1', ['4'] = '1', ['6'] = '2', ['8'] = '–' })
  on('Rearrange when formatting')
  keys('<Space>')
  M.settle(child)
  expect.equality(M.pane_lines(child, 'preview')[3], 'function M.f() end')
  expect.equality(preview_marks(), { {}, {} })
end

T['sort panel'] = MiniTest.new_set()

---@param slots table the stored Slots of the fake c
local function c_slots(slots)
  child:write_global({ version = 1, languages = { c = { arrangement = { slots = slots } } } })
end

T['sort panel']['off, by name and custom order, each one undo step'] = function()
  open_tab('c')
  expect.equality(rows(), { '[x] Rearrange when formatting', '[ ] Sort properties' })
  -- Formatted with the defaults: no spaces around `=`.
  expect.equality(M.pane_lines(child, 'preview'), { 'int width=1;', 'int top=2;', 'int color=3;', 'int align=4;' })
  on('Sort properties')
  keys('<Space>')
  expect.equality(rows(), { '[x] Rearrange when formatting', '[x] Sort properties', 'Order ‹By name›' })
  M.settle(child)
  expect.equality(M.pane_lines(child, 'preview'), { 'int align=4;', 'int color=3;', 'int top=2;', 'int width=1;' })
  on('Order')
  M.answer(child, { 'Custom order' })
  keys('<CR>')
  expect.equality(rows()[3], 'Order ‹Custom order›')
  -- It starts from the spec's default list.
  expect.equality(rows()[4], 'Custom order [color, width, align]')
  M.settle(child)
  -- `top` is in no Slot: it goes last.
  expect.equality(M.pane_lines(child, 'preview'), { 'int color=3;', 'int width=1;', 'int align=4;', 'int top=2;' })
  expect.equality(saved().languages.c.arrangement.slots, {
    { { name = 'color' } },
    { { name = 'width' } },
    { { name = 'align' } },
  })
  keys('h')
  expect.equality(rows()[3], 'Order ‹By name›')
  keys('u')
  expect.equality(rows()[3], 'Order ‹Custom order›')
  keys('x')
  expect.equality(rows(), { '[x] Rearrange when formatting', '[ ] Sort properties' })
end

T['sort panel']['<CR> on the custom order opens the list float: J/K move, o adds, dd deletes'] = function()
  c_slots({ { { name = 'color' } }, { { name = 'width' } } })
  open_tab('c')
  on('Custom order [')
  keys('<CR>')
  expect.equality(M.pane_lines(child, 'order'), { 'color', 'width' })
  keys('J')
  expect.equality(M.pane_lines(child, 'order'), { 'width', 'color' })
  keys({ 'o', 'top', '<Esc>' })
  keys({ 'gg', 'dd' })
  expect.equality(M.pane_lines(child, 'order'), { 'color', 'top' })
  keys('<CR>')
  expect.equality(M.pane_win(child, 'order'), nil)
  expect.equality(rows()[4], 'Custom order [color, top]')
end

T['sort panel']['a shape it cannot show falls back to the Slot rows with a note'] = function()
  c_slots({ { { name = 'col.*' } }, { { is = { 'declaration' } } } })
  open_tab('c')
  expect.equality(rows(), {
    '[x] Rearrange when formatting',
    '⚠ The sort panel cannot show this Arrangement, so it shows the Slot rows.',
    '',
    'Slots',
    '1 name /col.*/',
    '2 declaration',
    '',
    '▸ Aliases (0)',
  })
end

-- The screen of the value controls' screenshots (`test_menu_edit.lua`).
T['screenshots'] = MiniTest.new_set({
  hooks = {
    pre_case = function()
      child.o.lines, child.o.columns = 30, 120
    end,
  },
})

T['screenshots']['the rule float'] = function()
  lua_slots({
    { { is = { 'field' }, is_not = { 'private' } }, { is = { 'field' } } },
    { { is = { 'function' }, name = 'get.*', order = 'by_name' } },
    { { is = { 'method' } } },
  })
  open_tab('lua')
  on('get.*')
  M.screenshot(child, 'menu-arrangement')
  keys('<CR>')
  M.screenshot(child, 'menu-arrangement-rule')
end

T['screenshots']['the sort panel'] = function()
  c_slots({ { { name = 'color' } }, { { name = 'width' } }, { { name = 'align' } } })
  open_tab('c')
  M.screenshot(child, 'menu-arrangement-sort')
end

return T
