-- Embedded code (ADR-0008, ADR-0005, ADR-0007 `uses`, ADR-0015 `parser_key`):
-- fenced Lua in the fake `markdown` is grafted; the fake template host `tmpl`
-- on `markdown` merges its template layer, the fake `inl` on
-- `markdown_inline`. Every case formats a real buffer through `format{}`.

local H = dofile('tests/helpers.lua')
local expect = MiniTest.expect

local child = H.new_child()

local T = MiniTest.new_set({
  hooks = {
    pre_case = function()
      child:setup({
        plugins = {
          'codestyle-lua.nvim',
          'codestyle-markdown.nvim',
          'codestyle-tmpl.nvim',
          'codestyle-inl.nvim',
          'codestyle-useslua.nvim',
        },
      })
    end,
    post_case = function()
      child:teardown()
    end,
  },
})

--- Formats a buffer with these languages in the Global file.
---@param languages table
---@param filetype string
---@param lines string[]
---@return string[]
local function format(languages, filetype, lines)
  child:write_global({ version = 1, languages = languages })
  local buf = child:open_buffer({ filetype = filetype, lines = lines })
  child:format({ buf = buf })
  return child:lines(buf)
end

local lua = { spaces = { around_assignment = true }, indent = { size = 2 } }

T['graft'] = MiniTest.new_set()

T['graft']['a fenced Lua body is formatted by fake lua with its own Code Style and indent Options'] = function()
  local lines = { '  # Title', '```lua', 'if a then', 'x=1', '      end', '```', '' }

  expect.equality(format({ lua = lua }, 'markdown', lines), {
    '# Title',
    '```lua',
    'if a then',
    '  x = 1',
    'end',
    '```',
    '',
  })
  expect.equality(child:notices(), {})
end

T['graft']['a closing fence on the last line ends the fenced body, and no final line is added'] = function()
  -- A buffer has an implicit final newline: `markdown` reads the last
  -- line's fence as a fence only when the parsed text ends with one.
  local lines = { '```lua', 'x=1', '  ```' }

  expect.equality(format({ lua = lua }, 'markdown', lines), { '```lua', 'x = 1', '```' })
  expect.equality(child:notices(), {})
end

T['graft']["the host's override flag switches the body to the file's indent Options"] = function()
  local lines = { '```lua', 'if a then', 'x=1', 'end', '```', '' }
  local markdown = { indent = { same_in_whole_file = true, size = 3 } }

  expect.equality(format({ lua = lua, markdown = markdown }, 'markdown', lines), {
    '```lua',
    'if a then',
    '   x = 1',
    'end',
    '```',
    '',
  })
end

T['graft']["each line's whitespace uses the indent and tab Options of its first leaf Block"] = function()
  local lines = { '- item', '  ```lua', '  if a then', '  x=1', '  end', '  ```', '' }
  local markdown = { indent = { use_tab = true } }

  expect.equality(format({ lua = lua, markdown = markdown }, 'markdown', lines), {
    '- item',
    '\t```lua',
    '    if a then',
    '      x = 1',
    '    end',
    '\t```',
    '',
  })
end

T['graft']["an Embed Point with parser_key uses that key of the embedded spec's parsers"] = function()
  local lines = { '```lua parser=broken', '   x=1', '```', '```lua parser=broken', 'y=2', '```', '' }

  expect.equality(format({ lua = lua }, 'markdown', lines), {
    '```lua parser=broken',
    'x=1',
    '```',
    '```lua parser=broken',
    'y=2',
    '```',
    '',
  })
  expect.equality(child:notices(), {
    {
      level = H.levels.WARN,
      message = 'codestyle: codestyle-lua.nvim has no Tree-sitter parser for the embedded "lua" code,'
        .. ' which is kept as written; install one of: nosuchparser',
    },
  })
end

T['graft']['a part whose plugin is missing keeps its lines; only the Gap before it moves'] = function()
  local lines = { '```nope', '   a  =  1', '     b', '```', '' }

  expect.equality(format({ lua = lua }, 'markdown', lines), { '```nope', 'a  =  1', '     b', '```', '' })
  local buf = child:open_buffer({ filetype = 'markdown', lines = lines })
  child:format({ buf = buf })
  expect.equality(child:notices(), {
    {
      level = H.levels.WARN,
      message = 'codestyle: no Language Plugin for the embedded language "nope" is installed;'
        .. ' its code is kept as written',
    },
  })
end

T['graft']['a part whose builder returns nil is read-only, with one warning per buffer and language'] = function()
  local lines = { '```lua fragment=expression', '  x=1', '   y=2', '```', '' }

  expect.equality(
    format({ lua = lua }, 'markdown', lines),
    { '```lua fragment=expression', 'x=1', '   y=2', '```', '' }
  )
  child:format({ buf = 0 })
  local other = child:open_buffer({ filetype = 'markdown', lines = lines })
  child:format({ buf = other })
  local warning = {
    level = H.levels.WARN,
    message = 'codestyle: Language Plugin "lua" builds no Blocks for "expression" code; it is kept as written',
  }
  expect.equality(child:notices(), { warning, warning })
end

T['graft']['an ERROR node inside a part keeps only its own text'] = function()
  local lines = { '```lua', 'x=1', 'y==2', 'z=3', '```', '' }

  expect.equality(format({ lua = lua }, 'markdown', lines), { '```lua', 'x = 1', 'y==2', 'z = 3', '```', '' })
end

T['graft']["the right margin of a grafted part is the host file's (temporary default of the named seam)"] = function()
  local lines = { '```lua', 'f(aaaa, bbbb, cccc)', '```', '' }
  local wrapping = vim.tbl_extend('force', lua, { wrap = { call_arguments = 'if_long', hard_wrap_at = 10 } })

  -- The fake markdown's margin is `general.hard_wrap_at` (120); lua's own is 10.
  expect.equality(format({ lua = wrapping }, 'markdown', lines), lines)
  -- The same lines in a lua file wrap at lua's 10.
  expect.equality(format({ lua = wrapping }, 'lua', { 'f(aaaa, bbbb, cccc)' }), {
    'f(aaaa,',
    '        bbbb,',
    '        cccc)',
  })
end

T['uses'] = MiniTest.new_set()

T['uses']['a plugin gets ctx.values.<used> and the ctx.uses.<used> handlers'] = function()
  expect.equality(format({ lua = lua }, 'useslua', { 'x=1' }), { 'x = 1' })
  expect.equality(child:plugin_values().lua.spaces.around_assignment, true)

  expect.equality(format({ lua = { spaces = { around_assignment = false } } }, 'useslua', { 'x = 1' }), { 'x=1' })
  expect.equality(child:notices(), {})
end

T['template merge'] = MiniTest.new_set()

-- The host chooses the template layers' indent Options: `tmpl`'s 3, never `inl`'s 8.
local template = { tmpl = { indent = { size = 3 } }, inl = { indent = { size = 8 } } }

T['template merge']['a host Block that crosses a markup Block is split into its children'] = function()
  -- The emphasis runs from the first fenced body into the paragraph after it,
  -- so that fenced block crosses it: its closing delimiter joins the emphasis,
  -- which indents it. The second fenced block stays whole.
  local lines = { '```x', '*a', '```', 'b*', '```y', '```', '' }

  expect.equality(format(template, 'tmpl', lines), { '```x', '*a', '   ```', '   b*', '```y', '```', '' })
  expect.equality(child:notices(), {})
end

T['template merge']['the lowest Block that holds both leaves owns the Gap'] = function()
  -- The markup words of a fenced body sit in the host's fenced block, so its
  -- rules give their Gap (two spaces) and their indent; in a paragraph the
  -- markup root owns the Gap (one space).
  local lines = { 'p   q', '', '```x', 'p   q', '```', '' }

  expect.equality(format(template, 'tmpl', lines), { 'p q', '', '```x', '   p  q', '```', '' })
  -- A list item crosses the emphasis, so its marker `-` joins the emphasis,
  -- which owns the Gap after it (one space; the item's own rule says two).
  expect.equality(format(template, 'tmpl', { '*a', '-    b*', '' }), { '*a', '   - b*', '' })
  expect.equality(child:notices(), {})
end

T['template merge']['the host chooses the indent Options of the template layers'] = function()
  local lines = { '*a', 'b*', '' }

  expect.equality(format(template, 'tmpl', lines), { '*a', '   b*', '' })
  expect.equality(format({ tmpl = { indent = { size = 2 } } }, 'tmpl', lines), { '*a', '  b*', '' })
end

return T
