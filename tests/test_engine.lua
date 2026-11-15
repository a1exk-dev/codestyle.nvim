-- The Engine and the Format Run on real input (ADR-0002, ADR-0007): broken
-- code, rules for missing parser nodes, ranges, `before`/`after` steps and a
-- plugin's own `formatter.format`. Every case formats a real buffer through
-- the public `format{}`.

local H = dofile('tests/helpers.lua')
local expect = MiniTest.expect

local child = H.new_child()

local T = MiniTest.new_set({
  hooks = {
    pre_case = function()
      child:setup({ plugins = { 'codestyle-lua.nvim', 'codestyle-c.nvim', 'codestyle-luanext.nvim' } })
    end,
    post_case = function()
      child:teardown()
    end,
  },
})

---@param languages table
local function global(languages)
  child:write_global({ version = 1, languages = languages })
end

local spaces = { spaces = { around_assignment = true } }

T['broken code'] = MiniTest.new_set()

T['broken code']['an ERROR node keeps its text, and the rest of the file is formatted'] = function()
  global({ lua = spaces })
  local buf = child:open_buffer({ filetype = 'lua', lines = { 'x=1', 'y==2', 'z=3' } })

  child:format({ buf = buf })

  expect.equality(child:lines(buf), { 'x = 1', 'y==2', 'z = 3' })
  expect.equality(child:notices(), {})
end

T['broken code']['the line around a MISSING node keeps its text'] = function()
  global({ lua = spaces })
  local buf = child:open_buffer({ filetype = 'lua', lines = { 'x=1', 'y=f(1', 'z=3' } })

  child:format({ buf = buf })

  expect.equality(child:lines(buf), { 'x = 1', 'y=f(1', 'z = 3' })
end

T['broken code']['the lines of the node that a MISSING node leaves open keep their text'] = function()
  global({ lua = spaces })
  -- The parser reads `z=3` as a field of the table that has no `}`.
  local buf = child:open_buffer({ filetype = 'lua', lines = { 'x=1', 'y={a=1,', 'z=3' } })

  child:format({ buf = buf })

  expect.equality(child:lines(buf), { 'x = 1', 'y={a=1,', 'z=3' })
end

T['a rule whose node type the grammar lacks is skipped with one warning, and other rules apply'] = function()
  global({ luanext = spaces })
  local buf = child:open_buffer({ filetype = 'luanext', lines = { 'x=1' } })

  child:format({ buf = buf })
  child:format({ buf = buf })

  expect.equality(child:lines(buf), { 'x = 1' })
  expect.equality(child:notices(), {
    {
      level = H.levels.WARN,
      message = 'codestyle: Language Plugin "luanext" has a rule that needs the node type "augmented_assignment",'
        .. ' which the "lua" parser lacks; the rule is skipped',
    },
  })
end

T['range'] = MiniTest.new_set()

T['range']['formats only the Gaps inside those lines'] = function()
  global({ lua = spaces })
  local buf = child:open_buffer({ filetype = 'lua', lines = { 'x=1', 'y=2', 'z=3', 'w=4' } })

  child:format({ buf = buf, range = { 2, 3 } })

  expect.equality(child:lines(buf), { 'x=1', 'y = 2', 'z = 3', 'w=4' })
  expect.equality(child:notices(), {})
end

T['range']['includes the leading indent of its first line'] = function()
  -- The fake `c` formatter starts each top-level statement at column 0.
  global({ c = spaces })
  local buf = child:open_buffer({ filetype = 'c', lines = { '  int a=1;', '  b=2;', '  c=3;' } })

  child:format({ buf = buf, range = { 2, 2 } })

  expect.equality(child:lines(buf), { '  int a=1;', 'b = 2;', '  c=3;' })
  expect.equality(child:notices(), {})
end

T['steps'] = MiniTest.new_set()

T['steps']['before, the engine and after run in order, with a new parse between'] = function()
  -- `before` removes the `;`, which moves `y='a'` one column to the left; the
  -- engine spaces the `=`; `after` turns the quotes of the moved string.
  global({ lua = { spaces = { around_assignment = true }, conversion = { semicolons = true, double_quotes = true } } })
  local buf = child:open_buffer({ filetype = 'lua', lines = { "x=1; y='a'" } })

  child:format({ buf = buf })

  expect.equality(child:lines(buf), { 'x = 1 y = "a"' })
  expect.equality(child:notices(), {})
end

T['steps']['with a range, an edit outside it is dropped with a warning'] = function()
  global({ lua = { spaces = { around_assignment = true }, conversion = { double_quotes = true } } })
  local buf = child:open_buffer({ filetype = 'lua', lines = { "x='a'", "y='a'", "z='a'" } })

  child:format({ buf = buf, range = { 2, 2 } })

  expect.equality(child:lines(buf), { "x='a'", 'y = "a"', "z='a'" })
  expect.equality(child:notices(), {
    {
      level = H.levels.WARN,
      message = 'codestyle: Language Plugin "lua" changed text outside the range; the change is dropped',
    },
  })
end

T['formatter.format replaces the engine, and its edits undo in one step'] = function()
  global({ c = spaces })
  local buf = child:open_buffer({ filetype = 'c', lines = { 'int a=1;', '  b=2;' } })

  child:format({ buf = buf })

  expect.equality(child:lines(buf), { 'int a = 1;', 'b = 2;' })

  child.type_keys('u')

  expect.equality(child:lines(buf), { 'int a=1;', '  b=2;' })
end

return T
