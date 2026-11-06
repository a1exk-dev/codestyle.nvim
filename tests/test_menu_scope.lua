-- The Menu's keys that act on the whole Draft (ADR-0004, ADR-0006, ADR-0010):
-- `s` switches scope, `p` applies a Preset, `i` imports a Scheme XML and `R`
-- shows its report; `:Codestyle import [path]`. Read back from the panes, the
-- notices, the `vim.ui` calls (the user's picker) and the saved files.

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

---@param keys string|string[]
local function keys(keys)
  child.type_keys(keys)
  M.settle(child)
end

--- The row of a pane that holds the text, with each run of blanks as one space.
---@param pane string
---@param text string
---@return string?
local function row(pane, text)
  for _, line in ipairs(M.pane_rows(child, pane)) do
    if line:find(text, 1, true) then
      return line
    end
  end
end

--- Opens a lua buffer in the repo and the Menu on it.
local function open_in_repo()
  child:open_buffer({ lines = { 'x=1' }, filetype = 'lua', name = child.paths.repo .. '/init.lua' })
  M.open_menu(child)
end

---@param path string
---@return table
local function read_json(path)
  return vim.json.decode(table.concat(vim.fn.readfile(path), '\n'))
end

--- A `<code_scheme>` with the fake lua's indent.
---@param size integer
---@return string
local function scheme_xml(size)
  return table.concat({
    '<code_scheme name="Project" version="173">',
    '  <codeStyleSettings language="Lua">',
    '    <indentOptions>',
    ('      <option name="INDENT_SIZE" value="%d" />'):format(size),
    '    </indentOptions>',
    '  </codeStyleSettings>',
    '</code_scheme>',
    '',
  }, '\n')
end

local function write_project_xml(size)
  child:write_file(child.paths.repo .. '/.idea/codeStyles/Project.xml', scheme_xml(size))
end

T['p'] = MiniTest.new_set()

T['p']['lists the plugin Presets, then the user ones marked (user); applying one is one undo step'] = function()
  child.lua([[require('codestyle').setup({ presets = {
    { name = 'Team', language = 'lua', values = { lua = { indent = { size = 3 } } } },
    { name = 'Other', language = 'c', values = {} },
  } })]])
  open_in_repo()
  M.answer(child, { 'Team (user)' })
  keys('p')
  local call = M.ui_calls(child)[1]
  expect.equality(call.kind, 'select')
  expect.equality(call.items, { 'Roomy', 'Mixed', 'Team (user)' })
  expect.equality(row('languages', 'Lua'), 'Lua •1')
  keys('u')
  expect.equality(row('languages', 'Lua'), 'Lua')
  keys('<C-r>')
  expect.equality(row('languages', 'Lua'), 'Lua •1')
  expect.equality(child:notices(), {})
end

T['p']['one notice lists what a Preset skipped'] = function()
  open_in_repo()
  M.answer(child, { 'Mixed' })
  keys('p')
  local notices = child:notices()
  expect.equality(#notices, 1)
  expect.equality(notices[1].level, H.levels.WARN)
  expect.equality(vim.startswith(notices[1].message, 'codestyle: Preset "Mixed" skipped'), true)
  expect.equality(row('languages', 'Lua'), 'Lua •1')
end

T['p']['a language with no Presets says so'] = function()
  open_in_repo()
  M.cursor_on(child, 'languages', 'General')
  keys('<C-l>')
  keys('p')
  expect.equality(M.ui_calls(child), {})
  expect.equality(child:notices(), { { level = H.levels.INFO, message = 'codestyle: General has no Presets' } })
end

T['i'] = MiniTest.new_set()

T['i']['imports the repo Project.xml into the edited scope as one undo step'] = function()
  write_project_xml(2)
  open_in_repo()
  keys('i')
  expect.equality(M.ui_calls(child), {})
  expect.equality(row('languages', 'Lua'), 'Lua •1')
  local notices = child:notices()
  expect.equality(#notices, 1)
  expect.equality(notices[1].level, H.levels.INFO)
  expect.equality(vim.startswith(notices[1].message, 'codestyle: imported ' .. child.paths.repo), true)
  keys('u')
  expect.equality(row('languages', 'Lua'), 'Lua')
  keys({ '<C-r>', '<C-s>' })
  expect.equality(read_json(child.paths.config .. '/codestyle.json').languages, { lua = { indent = { size = 2 } } })
end

T['i']['asks for a path when the repo has no Project.xml'] = function()
  local path = child.paths.root .. '/scheme.xml'
  child:write_file(path, scheme_xml(3))
  open_in_repo()
  M.answer(child, { vim.NIL, path })
  keys('i')
  expect.equality(row('languages', 'Lua'), 'Lua')
  keys('i')
  expect.equality(row('languages', 'Lua'), 'Lua •1')
  local calls = M.ui_calls(child)
  expect.equality(#calls, 2)
  expect.equality(calls[1].kind, 'input')
  expect.equality(calls[1].prompt, 'Import Scheme XML: ')
end

T['i']['malformed XML shows the error and leaves the Draft unchanged'] = function()
  child:write_file(child.paths.repo .. '/.idea/codeStyles/Project.xml', '<code_scheme>\n  <option name="A"\n')
  open_in_repo()
  M.answer(child, { 'Roomy' })
  keys('p')
  local before = #child:notices()
  keys('i')
  expect.equality(row('languages', 'Lua'), 'Lua •2')
  local notices = vim.list_slice(child:notices(), before + 1)
  expect.equality(#notices, 1)
  expect.equality(notices[1].level, H.levels.ERROR)
  expect.equality(notices[1].message:find('Project.xml:%d+: .*nothing was imported') ~= nil, true)
  keys('R')
  expect.equality(M.pane_win(child, 'report'), nil)
end

T['R'] = MiniTest.new_set()

T['R']['opens the full report of the last import, per language'] = function()
  write_project_xml(2)
  open_in_repo()
  keys('R')
  expect.equality(M.pane_win(child, 'report'), nil)
  expect.equality(child:notices()[1].message, 'codestyle: no import to report; i imports a Scheme XML')
  keys({ 'i', 'R' })
  local lines = M.pane_lines(child, 'report')
  expect.equality(lines[1], 'Imported ' .. child.paths.repo .. '/.idea/codeStyles/Project.xml')
  expect.equality(vim.list_contains(lines, 'Lua'), true)
  expect.equality(vim.list_contains(lines, '    indent.size = 2'), true)
  keys('q')
  expect.equality(M.pane_win(child, 'report'), nil)
  expect.equality(child.api.nvim_get_current_win(), M.pane_win(child, 'options'))
end

T[':Codestyle import'] = MiniTest.new_set()

T[':Codestyle import']['[path] opens the Menu and imports'] = function()
  local path = child.paths.root .. '/scheme.xml'
  child:write_file(path, scheme_xml(3))
  child:open_buffer({ lines = { 'x=1' }, filetype = 'lua', name = child.paths.repo .. '/init.lua' })
  child.cmd('Codestyle import ' .. path)
  M.settle(child)
  expect.equality(row('languages', 'Lua'), 'Lua •1')
  expect.equality(M.ui_calls(child), {})
  keys('R')
  expect.equality(M.pane_lines(child, 'report')[1], 'Imported ' .. path)
end

T[':Codestyle import']['with no path uses Project.xml'] = function()
  write_project_xml(2)
  child:open_buffer({ lines = { 'x=1' }, filetype = 'lua', name = child.paths.repo .. '/init.lua' })
  child.cmd('Codestyle import')
  M.settle(child)
  expect.equality(row('languages', 'Lua'), 'Lua •1')
end

T[':Codestyle import']['completes the subcommand, then file paths'] = function()
  child:write_file(child.paths.root .. '/scheme.xml', scheme_xml(3))
  child.fn.chdir(child.paths.root)
  expect.equality(child.fn.getcompletion('Codestyle im', 'cmdline'), { 'import' })
  expect.equality(child.fn.getcompletion('Codestyle import sch', 'cmdline'), { 'scheme.xml' })
end

T['the language list'] = MiniTest.new_set()

T['the language list']['shows "Project.xml found [i] import" until the repo has .codestyle.json'] = function()
  write_project_xml(2)
  open_in_repo()
  expect.equality(row('languages', 'Project.xml found'), 'Project.xml found [i] import')
  keys('q')
  child:write_file(child.paths.repo .. '/.codestyle.json', '{"version": 1}')
  M.open_menu(child)
  expect.equality(row('languages', 'Project.xml found'), nil)
end

T['s'] = MiniTest.new_set()

--- The scope that the language list shows.
local function scope()
  return M.pane_lines(child, 'languages')[1]
end

T['s']['switches between the Project and the Global Code Style'] = function()
  child:write_global({ version = 1, languages = { lua = { indent = { size = 3 } } } })
  child:write_file(child.paths.repo .. '/.codestyle.json', { version = 1 })
  open_in_repo()
  expect.equality(scope(), 'Project Code Style')
  expect.equality(row('languages', 'Lua'), 'Lua')
  keys('s')
  expect.equality(scope(), 'Global Code Style')
  expect.equality(row('languages', 'Lua'), 'Lua •1')
  keys('s')
  expect.equality(scope(), 'Project Code Style')
  expect.equality(M.ui_calls(child), {})
  expect.equality(child.api.nvim_get_current_win(), M.pane_win(child, 'options'))
end

T['s']['the first switch offers to copy Global or start from the defaults'] = function()
  child:write_global({ version = 1, languages = { lua = { indent = { size = 3 } } } })
  open_in_repo()
  M.answer(child, { 'Copy' })
  keys('s')
  local call = M.ui_calls(child)[1]
  expect.equality(call.kind, 'select')
  expect.equality(call.items, { 'Copy the Global Code Style', 'Start from the defaults' })
  expect.equality(scope(), 'Project Code Style')
  expect.equality(row('languages', 'Lua'), 'Lua •1')
  keys('<C-s>')
  expect.equality(read_json(child.paths.repo .. '/.codestyle.json').languages, { lua = { indent = { size = 3 } } })
end

T['s']['starting from the defaults'] = function()
  child:write_global({ version = 1, languages = { lua = { indent = { size = 3 } } } })
  open_in_repo()
  M.answer(child, { 'defaults' })
  keys('s')
  expect.equality(scope(), 'Project Code Style')
  expect.equality(row('languages', 'Lua'), 'Lua')
  keys('<C-s>')
  expect.equality(read_json(child.paths.repo .. '/.codestyle.json'), { version = 1 })
end

T['s']['the first switch offers to import Project.xml when the repo has it'] = function()
  write_project_xml(2)
  open_in_repo()
  M.answer(child, { 'Import' })
  keys('s')
  expect.equality(M.ui_calls(child)[1].items, {
    'Copy the Global Code Style',
    'Start from the defaults',
    'Import .idea/codeStyles/Project.xml',
  })
  expect.equality(scope(), 'Project Code Style')
  expect.equality(row('languages', 'Lua'), 'Lua •1')
  keys('R')
  expect.equality(M.pane_lines(child, 'report')[1], 'Imported ' .. child.paths.repo .. '/.idea/codeStyles/Project.xml')
end

T['s']['cancelling the offer keeps the Global Code Style'] = function()
  open_in_repo()
  M.answer(child, { 'no such choice' })
  keys('s')
  expect.equality(M.ui_calls(child)[1].kind, 'select')
  expect.equality(scope(), 'Global Code Style')
  expect.equality(vim.fn.filereadable(child.paths.repo .. '/.codestyle.json'), 0)
end

T['s']['asks Save / Discard / Cancel first when the Draft has changes'] = function()
  child:write_file(child.paths.repo .. '/.codestyle.json', { version = 1 })
  open_in_repo()
  M.answer(child, { 'Roomy', 'Cancel' })
  keys({ 'p', 's' })
  expect.equality(M.ui_calls(child)[2].items, { 'Save', 'Discard', 'Cancel' })
  expect.equality(scope(), 'Project Code Style')
  expect.equality(row('languages', 'Lua'), 'Lua •2')
  M.answer(child, { 'Discard' })
  keys('s')
  expect.equality(scope(), 'Global Code Style')
  keys('s')
  expect.equality(row('languages', 'Lua'), 'Lua')
end

T['s']['outside a repo there is no Project Code Style'] = function()
  child:open_buffer({ lines = { 'x=1' }, filetype = 'lua', name = child.paths.root .. '/loose/init.lua' })
  M.open_menu(child)
  keys('s')
  expect.equality(scope(), 'Global Code Style')
  expect.equality(child:notices(), {
    {
      level = H.levels.WARN,
      message = 'codestyle: no Project Code Style: the buffer is in no folder with .codestyle.json or .git',
    },
  })
end

return T
