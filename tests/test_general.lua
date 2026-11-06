-- `general` and the rules for the whole file (ADR-0018): formatter markers,
-- Do not format, line endings and trailing spaces. Every case formats a real
-- buffer through the public `format{}`.

local H = dofile('tests/helpers.lua')
local expect = MiniTest.expect

local child = H.new_child()

local T = MiniTest.new_set({
  hooks = {
    pre_case = function()
      child:setup({ plugins = { 'codestyle-lua.nvim', 'codestyle-markdown.nvim' } })
    end,
    post_case = function()
      child:teardown()
    end,
  },
})

--- Writes the Global Code Style with `spaces.around_assignment` on for `lua`.
---@param general? table
local function global(general)
  child:write_global({
    version = 1,
    languages = { general = general, lua = { spaces = { around_assignment = true } } },
  })
end

---@param lines string[]
---@param opts? { range?: integer[], name?: string }
---@return string[]
local function format_lua(lines, opts)
  opts = opts or {}
  local buf = child:open_buffer({ filetype = 'lua', lines = lines, name = opts.name })
  child:format({ buf = buf, range = opts.range })
  return child:lines(buf)
end

T['markers'] = MiniTest.new_set()

T['markers']['text between the default markers keeps its layout; the off-marker line is formatted'] = function()
  global()

  local lines = format_lua({ 'a=1 -- @formatter:off', 'b=2', '-- @formatter:on', 'c=3' })

  expect.equality(lines, { 'a = 1 -- @formatter:off', 'b=2', '-- @formatter:on', 'c = 3' })
  expect.equality(child:notices(), {})
end

T['markers']['in plain mode the first character matches exactly and the rest ignores case'] = function()
  global()

  local lines = format_lua({ '-- @FORMATTER:OFF', 'a=1', '-- @Formatter:On', 'b=2', '-- formatter:off', 'c=3' })

  expect.equality(lines, { '-- @FORMATTER:OFF', 'a=1', '-- @Formatter:On', 'b = 2', '-- formatter:off', 'c = 3' })
end

T['markers']['the first on-marker closes the region, so markers do not nest'] = function()
  global()

  local lines = format_lua({
    '-- @formatter:off',
    'a=1',
    '-- @formatter:off',
    'b=2',
    '-- @formatter:on',
    'c=3',
    '-- @formatter:on',
    'd=4',
  })

  expect.equality(lines, {
    '-- @formatter:off',
    'a=1',
    '-- @formatter:off',
    'b=2',
    '-- @formatter:on',
    'c = 3',
    '-- @formatter:on',
    'd = 4',
  })
end

T['markers']['an off-marker with no on-marker keeps the rest of the file'] = function()
  global()

  local lines = format_lua({ 'a=1', 's = "@formatter:off"', 'b=2', 'c=3' })

  expect.equality(lines, { 'a = 1', 's = "@formatter:off"', 'b=2', 'c=3' })
end

T['markers']['regex mode uses case-sensitive Vim regexes'] = function()
  global({ markers = { regex = true, off = [[fmt:\(off\|skip\)]], on = 'fmt:on' } })

  local lines = format_lua({ '-- fmt:skip', 'a=1', '-- fmt:on', 'b=2', '-- FMT:OFF', 'c=3' })

  expect.equality(lines, { '-- fmt:skip', 'a=1', '-- fmt:on', 'b = 2', '-- FMT:OFF', 'c = 3' })
end

T['markers']['a tag that is not a valid Vim regex turns markers off with one warning'] = function()
  global({ markers = { regex = true, off = [[fmt:\(off]] } })

  expect.equality(format_lua({ '-- fmt:off', 'a=1' }), { '-- fmt:off', 'a = 1' })
  child:format()

  expect.equality(child:notices(), {
    {
      message = [[codestyle: formatter marker "fmt:\\(off" is not a valid Vim regex; markers are off]],
      level = H.levels.WARN,
    },
  })
end

T['markers']['markers.enabled = false turns markers off'] = function()
  global({ markers = { enabled = false } })

  local lines = format_lua({ '-- @formatter:off', 'a=1', '-- @formatter:on' })

  expect.equality(lines, { '-- @formatter:off', 'a = 1', '-- @formatter:on' })
end

T['markers']['a selection inside a region changes nothing'] = function()
  global()

  local lines = format_lua({ '-- @formatter:off', 'a=1', 'b=2', '-- @formatter:on' }, { range = { 2, 3 } })

  expect.equality(lines, { '-- @formatter:off', 'a=1', 'b=2', '-- @formatter:on' })
  expect.equality(child:notices(), {})
end

T['markers']['the on-marker line is formatted by default'] = function()
  global()

  local lines = format_lua({ '-- @formatter:off', 'a=1', 'b=2 -- @formatter:on' })

  expect.equality(lines, { '-- @formatter:off', 'a=1', 'b = 2 -- @formatter:on' })
end

T['markers']['with the spec flag the on-marker line keeps its column'] = function()
  local buf = child:open_buffer({
    filetype = 'markdown',
    lines = { '  <!-- @formatter:off -->', '  kept', '  <!-- @formatter:on -->', '  moved' },
  })

  child:format({ buf = buf })

  expect.equality(child:lines(buf), { '<!-- @formatter:off -->', '  kept', '  <!-- @formatter:on -->', 'moved' })
end

T['do not format'] = MiniTest.new_set()

T['do not format']['a glob matched from the repo root skips the whole run with one notice per buffer'] = function()
  global({ do_not_format = { 'vendor/**' } })
  local skipped = child:open_buffer({ filetype = 'lua', lines = { 'a=1' }, name = child.paths.repo .. '/vendor/x.lua' })

  child:format({ buf = skipped })
  child:format({ buf = skipped })

  expect.equality(child:lines(skipped), { 'a=1' })
  expect.equality(child:notices(), {
    {
      message = 'codestyle: "vendor/x.lua" matches the Do not format pattern "vendor/**"; it is not formatted',
      level = H.levels.INFO,
    },
  })
  local formatted = format_lua({ 'a=1' }, { name = child.paths.repo .. '/src/vendor/x.lua' })
  expect.equality(formatted, { 'a = 1' })
end

T['do not format']['a glob with no slash matches the file name in any folder'] = function()
  global({ do_not_format = { '*.min.lua' } })

  local lines = format_lua({ 'a=1' }, { name = child.paths.repo .. '/a/b/c.min.lua' })

  expect.equality(lines, { 'a=1' })
  expect.equality(#child:notices(), 1)
end

T['do not format']['outside a repo, globs match from the working directory'] = function()
  global({ do_not_format = { 'lib/*.lua' } })
  local outside = child.paths.root .. '/outside'
  vim.fn.mkdir(outside, 'p')
  child.fn.chdir(outside)

  expect.equality(format_lua({ 'a=1' }, { name = outside .. '/lib/x.lua' }), { 'a=1' })
  expect.equality(format_lua({ 'a=1' }, { name = outside .. '/src/lib/x.lua' }), { 'a = 1' })
end

T['line endings'] = MiniTest.new_set()

---@param lines string[]
---@return string[] lines
---@return string fileformat
local function format_endings(lines)
  global()
  local buf = child:open_buffer({ filetype = 'lua', lines = lines })
  child:format({ buf = buf })
  return child:lines(buf), child.api.nvim_get_option_value('fileformat', { buf = buf })
end

T['line endings']['mixed endings convert to LF when most lines use LF'] = function()
  local lines, fileformat = format_endings({ 'a=1\r', 'b=2', 'c=3' })

  expect.equality(lines, { 'a = 1', 'b = 2', 'c = 3' })
  expect.equality(fileformat, 'unix')
end

T['line endings']['mixed endings convert to CRLF when most lines use it, and fileformat becomes dos'] = function()
  local lines, fileformat = format_endings({ 'a=1\r', 'b=2\r', 'c=3' })

  expect.equality(lines, { 'a = 1', 'b = 2', 'c = 3' })
  expect.equality(fileformat, 'dos')
end

T['line endings']['a tie converts to LF'] = function()
  local lines, fileformat = format_endings({ 'a=1\r', 'b=2' })

  expect.equality(lines, { 'a = 1', 'b = 2' })
  expect.equality(fileformat, 'unix')
end

T['line endings']['a file with one ending keeps it'] = function()
  global()
  local buf = child:open_buffer({ filetype = 'lua', lines = { 'a=1', 'b=2' } })
  child.api.nvim_set_option_value('fileformat', 'dos', { buf = buf })

  child:format({ buf = buf })

  expect.equality(child:lines(buf), { 'a = 1', 'b = 2' })
  expect.equality(child.api.nvim_get_option_value('fileformat', { buf = buf }), 'dos')
end

T['trailing spaces'] = MiniTest.new_set()

T['trailing spaces']['trailing blanks go only on the changed lines, and no final newline is added'] = function()
  global()

  local lines = format_lua({ 'a=1 \t', 'b = 2  ', 'c=3' })

  expect.equality(lines, { 'a = 1', 'b = 2  ', 'c = 3' })
end

---@param keep boolean "Keep indents on empty lines"
---@return string[]
local function format_blank_line(keep)
  child:write_global({
    version = 1,
    languages = { lua = { conversion = { semicolons = true }, indent = { keep_on_empty_lines = keep } } },
  })
  return format_lua({ 'do', '  ;', 'end' })
end

T['trailing spaces']['the indent that "Keep indents on empty lines" puts on a blank line stays'] = function()
  expect.equality(format_blank_line(true), { 'do', '  ', 'end' })
end

T['trailing spaces']['a changed blank line loses its blanks when indents on empty lines are not kept'] = function()
  expect.equality(format_blank_line(false), { 'do', '', 'end' })
end

return T
