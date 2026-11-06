-- The Engine's layout of one language (ADR-0002, ADR-0007): Spacing through
-- `SpacingBuilder`, Indent, continuation indent, Wrap and Alignment, on the
-- fake `lua` plugin, through real buffers.

local H = dofile('tests/helpers.lua')
local expect = MiniTest.expect

local child = H.new_child()

local T = MiniTest.new_set({
  hooks = {
    pre_case = function()
      child:setup()
    end,
    post_case = function()
      child:teardown()
    end,
  },
})

--- Formats a `lua` buffer with these `lua` values in the Global file.
---@param lua table
---@param lines string[]
---@param general? table
---@return string[]
local function format(lua, lines, general)
  -- An empty table would be written as a JSON array.
  local languages = { lua = next(lua) and lua or vim.empty_dict(), general = general }
  child:write_global({ version = 1, languages = languages })
  local buf = child:open_buffer({ filetype = 'lua', lines = lines })
  child:format({ buf = buf })
  expect.equality(child:notices(), {})
  return child:lines(buf)
end

T['Spacing'] = MiniTest.new_set()

T['Spacing']['a rule written with SpacingBuilder applies'] = function()
  expect.equality(format({}, { 'f(a,b,  c)' }), { 'f(a, b, c)' })
end

T['Spacing']['a rule follows its Option'] = function()
  expect.equality(format({ spaces = { after_comma = false } }, { 'f(a, b,  c)' }), { 'f(a,b,c)' })
end

T['Spacing']['blank lines are kept up to their Option'] = function()
  local lines = { 'x=1', '', '', '', '', 'y=2', '', 'z=3' }

  expect.equality(format({}, lines), { 'x=1', '', '', 'y=2', '', 'z=3' })
  expect.equality(format({ blank_lines = { keep_in_code = 0 } }, lines), { 'x=1', 'y=2', 'z=3' })
end

T['Indent'] = MiniTest.new_set()

T['Indent']['nested Blocks get their indent'] = function()
  local lines = {
    'function f(a)',
    'if a then',
    '        return 1',
    '  end',
    'end',
    'local t = {',
    'x = 1,',
    '}',
  }

  expect.equality(format({ spaces = { around_assignment = true }, indent = { size = 2 } }, lines), {
    'function f(a)',
    '  if a then',
    '    return 1',
    '  end',
    'end',
    'local t = {',
    '  x = 1,',
    '}',
  })
end

T['Indent']['continuation lines get the continuation indent'] = function()
  local lines = { 'local x = 1 +', '2', 'f(a,', '  b)' }

  expect.equality(format({ spaces = { around_assignment = true }, indent = { continuation = 6 } }, lines), {
    'local x = 1 +',
    '      2',
    'f(a,',
    '      b)',
  })
end

T['Wrap'] = MiniTest.new_set()

T['Wrap']['call arguments do not wrap by default'] = function()
  local lines = { 'foo(aaaa, bbbb, cccc, dddd)' }

  expect.equality(format({ wrap = { hard_wrap_at = 20 } }, lines), lines)
end

T['Wrap']['wrap if long breaks before the last argument that fits'] = function()
  local lines = { 'foo(aaaa, bbbb, cccc, dddd, eeee, ffff)' }

  expect.equality(format({ wrap = { call_arguments = 'if_long', hard_wrap_at = 20 } }, lines), {
    'foo(aaaa, bbbb,',
    '        cccc, dddd,',
    '        eeee, ffff)',
  })
end

T['Wrap']['wrap if long uses hard_wrap_at of general'] = function()
  local lines = { 'foo(aaaa, bbbb, cccc, dddd)' }

  expect.equality(format({ wrap = { call_arguments = 'if_long' } }, lines, { hard_wrap_at = 20 }), {
    'foo(aaaa, bbbb,',
    '        cccc, dddd)',
  })
end

T['Wrap']['chop down if long puts every argument on its own line'] = function()
  local lines = { 'foo(aaaa, bbbb, cccc, dddd)', 'foo(a, b)' }

  expect.equality(format({ wrap = { call_arguments = 'chop_down', hard_wrap_at = 20 } }, lines), {
    'foo(aaaa,',
    '        bbbb,',
    '        cccc,',
    '        dddd)',
    'foo(a, b)',
  })
end

T['Wrap']['a line that fits is not wrapped, and kept line breaks stay'] = function()
  local lines = { 'foo(aaaa,', '        bbbb, cccc)' }

  expect.equality(format({ wrap = { call_arguments = 'chop_down', hard_wrap_at = 20 } }, lines), lines)
end

T['Alignment'] = MiniTest.new_set()

T['Alignment']['table fields align when the Option is on'] = function()
  local lines = { 'local t = {', '    a = 1,', '    bbb = 2,', '    cc = 3,', '}' }
  local lua = { spaces = { around_assignment = true }, align = { table_fields = true } }

  expect.equality(format(lua, lines), { 'local t = {', '    a   = 1,', '    bbb = 2,', '    cc  = 3,', '}' })
end

T['Alignment']['table fields keep one space when the Option is off'] = function()
  local lines = { 'local t = {', '    a   = 1,', '    bbb = 2,', '}' }

  expect.equality(format({ spaces = { around_assignment = true } }, lines), {
    'local t = {',
    '    a = 1,',
    '    bbb = 2,',
    '}',
  })
end

T['Alignment']['multiline call arguments align with the first one'] = function()
  local lines = { 'foo(a,', 'b,', '  c)' }

  expect.equality(format({ align = { call_arguments = true } }, lines), { 'foo(a,', '    b,', '    c)' })
end

T['Indent']['a range reindents only its own lines, from the kept lines around it'] = function()
  child:write_global({ version = 1, languages = { lua = { indent = { size = 2 } } } })
  local lines = { 'if a then', '      f()', 'g()', '      h()', 'end' }
  local buf = child:open_buffer({ filetype = 'lua', lines = lines })

  child:format({ buf = buf, range = { 3, 3 } })

  expect.equality(child:lines(buf), { 'if a then', '      f()', '      g()', '      h()', 'end' })
end

T["the user's layout is kept where no Option asks for a change"] = function()
  local lines = {
    '-- a comment',
    'local x = f( a, b )   -- trailing',
    '',
    'if x then',
    '    return { x = 1,',
    '        "s",',
    '    }',
    'end',
    'g(a,',
    '        b)',
  }

  expect.equality(format({ spaces = { around_assignment = true } }, lines), lines)
end

return T
