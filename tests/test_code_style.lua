-- Code Style storage and the Option model (ADR-0001, ADR-0003, ADR-0007,
-- ADR-0018): a Code Style file, a buffer in the fake `lua` language, a format,
-- the lines and notices read back.

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

local spaces_around_assignment = {
  version = 1,
  languages = { lua = { spaces = { around_assignment = true } } },
}

T['Project file'] = MiniTest.new_set()

T['Project file']['replaces the Global file completely'] = function()
  child:write_global(spaces_around_assignment)
  child:write_file(child.paths.repo .. '/.codestyle.json', { version = 1, languages = { lua = {} } })
  local buf = child:open_buffer({ filetype = 'lua', name = child.paths.repo .. '/src/a.lua', lines = { 'x = 1' } })

  child:format({ buf = buf })

  -- The Global file sets spaces.around_assignment; the Project file does not,
  -- so the plugin default (false) applies.
  expect.equality(child:lines(buf), { 'x=1' })
end

T['Project file']['is found at the nearest folder with .codestyle.json, above a nearer .git'] = function()
  child:write_file(child.paths.repo .. '/.codestyle.json', spaces_around_assignment)
  vim.fn.mkdir(child.paths.repo .. '/vendor/inner/.git', 'p')
  local path = child.paths.repo .. '/vendor/inner/a.lua'
  local buf = child:open_buffer({ filetype = 'lua', name = path, lines = { 'x=1' } })

  child:format({ buf = buf })

  expect.equality(child:lines(buf), { 'x = 1' })
end

T['broken file'] = MiniTest.new_set()

T['broken file']['not valid JSON gives one ERROR with file and line, and the buffer stays unchanged'] = function()
  local path = child.paths.repo .. '/.codestyle.json'
  child:write_file(path, '{\n  "version": 1,\n  "languages": {\n    "lua": {,}\n  }\n}\n')
  local buf = child:open_buffer({ filetype = 'lua', name = child.paths.repo .. '/a.lua', lines = { 'x = 1' } })

  child:format({ buf = buf })

  expect.equality(child:lines(buf), { 'x = 1' })
  expect.equality(child:notices(), {
    {
      level = H.levels.ERROR,
      message = ('codestyle: %s:4: not valid JSON (Expected object key string but found T_COMMA); nothing is formatted with this Code Style'):format(
        path
      ),
    },
  })
end

T['broken file']['an unknown version gives one ERROR with file and line'] = function()
  child:write_global('{\n  "languages": {},\n  "version": 2\n}\n')
  local buf = child:open_buffer({ filetype = 'lua', lines = { 'x = 1' } })

  child:format({ buf = buf })

  expect.equality(child:lines(buf), { 'x = 1' })
  expect.equality(child:notices(), {
    {
      level = H.levels.ERROR,
      message = ('codestyle: %s:3: unknown version 2, this Core reads version 1; nothing is formatted with this Code Style'):format(
        child.paths.config .. '/codestyle.json'
      ),
    },
  })
end

--- Formats a `lua` buffer with this `lua` table in the Global file, and
--- returns the values that the plugin got.
---@param lua table
---@return table
local function values_with(lua)
  child:write_global({ version = 1, languages = { lua = lua } })
  local buf = child:open_buffer({ filetype = 'lua', lines = { 'x = 1' } })
  child:format({ buf = buf })
  return child:plugin_values()
end

local general_defaults = {
  hard_wrap_at = 120,
  do_not_format = {},
  markers = { enabled = true, off = '@formatter:off', on = '@formatter:on', regex = false },
}

T['Option types'] = MiniTest.new_set()

T['Option types']['values of all six types are read'] = function()
  local values = values_with({
    spaces = { around_assignment = true },
    indent = { size = 2 },
    wrap = { call_arguments = 'chop_down', hard_wrap_at = 80, visual_guides = { 80, 100 } },
    comments = { todo = 'FIXME' },
    names = { globals = { 'vim', 'describe' } },
    members = { order = { 'metamethods', 'fields', 'methods' } },
  })

  expect.equality(values, {
    spaces = { around_assignment = true },
    indent = { size = 2 },
    wrap = { call_arguments = 'chop_down', hard_wrap_at = 80, visual_guides = { 80, 100 } },
    comments = { todo = 'FIXME' },
    names = { globals = { 'vim', 'describe' } },
    members = { order = { 'metamethods', 'fields', 'methods' } },
    general = general_defaults,
  })
  expect.equality(child:notices(), {})
end

T['Option types']['each invalid value gives one WARN per file, and the default is used'] = function()
  local lua = {
    spaces = { around_assignment = 'yes' },
    indent = { size = 40 },
    wrap = { call_arguments = 'sometimes', hard_wrap_at = 1.5, visual_guides = { 80, 'x' } },
    comments = { todo = vim.NIL },
    names = { globals = 'vim' },
    members = { order = { 'fields', 'fields', 'methods' } },
  }
  local path = child.paths.config .. '/codestyle.json'

  local values = values_with(lua)
  -- A second format of another buffer with the same file stays quiet.
  child:format({ buf = child:open_buffer({ filetype = 'lua', lines = { 'y = 2' } }) })

  expect.equality(values, {
    spaces = { around_assignment = false },
    indent = { size = 4 },
    wrap = { call_arguments = 'off', hard_wrap_at = 120, visual_guides = {} },
    comments = { todo = 'TODO' },
    names = { globals = { 'vim' } },
    members = { order = { 'fields', 'methods', 'metamethods' } },
    general = general_defaults,
  })
  expect.equality(child:notices(), {
    {
      level = H.levels.WARN,
      message = 'codestyle: '
        .. path
        .. ': invalid values, their defaults are used: '
        .. 'lua.spaces.around_assignment: expected a boolean, got "yes"; '
        .. 'lua.indent.size: 40 is out of range 0–32; '
        .. 'lua.wrap.call_arguments: unknown choice "sometimes"; '
        .. 'lua.wrap.hard_wrap_at: expected an integer, got 1.5; '
        .. 'lua.wrap.visual_guides: item 2: expected an integer, got "x"; '
        .. 'lua.comments.todo: expected a string, got null; '
        .. 'lua.names.globals: expected a list, got "vim"; '
        .. 'lua.members.order: expected an order of distinct members, got ["fields","fields","methods"]',
    },
  })
end

T['Option types']['a stored false is read'] = function()
  child:write_global({ version = 1, languages = { general = { markers = { enabled = false } } } })
  local buf = child:open_buffer({ filetype = 'lua', lines = { 'x = 1' } })

  child:format({ buf = buf })

  expect.equality(child:plugin_values().general.markers.enabled, false)
end

T['Option types']['a value where an object of Options belongs warns once, and the defaults are used'] = function()
  local values = values_with({ wrap = 5 })

  expect.equality(values.wrap, { call_arguments = 'off', hard_wrap_at = 120, visual_guides = {} })
  expect.equality(child:notices(), {
    {
      level = H.levels.WARN,
      message = 'codestyle: '
        .. child.paths.config
        .. '/codestyle.json: invalid values, their defaults are used: lua.wrap: expected an object, got 5',
    },
  })
end

T['order'] = MiniTest.new_set()

T['order']['a missing member goes where the default puts it, and an unknown member is ignored'] = function()
  -- Default: fields, methods, metamethods. metamethods follows methods.
  local values = values_with({ members = { order = { 'methods', 'constants', 'fields' } } })

  expect.equality(values.members.order, { 'methods', 'metamethods', 'fields' })
  expect.equality(child:notices(), {})
end

T['order']['a missing first member goes to the front'] = function()
  local values = values_with({ members = { order = { 'metamethods', 'methods' } } })

  expect.equality(values.members.order, { 'fields', 'metamethods', 'methods' })
end

T['general'] = MiniTest.new_set()

T['general']['an Option that inherits hard_wrap_at uses the general value when unset'] = function()
  child:write_global({ version = 1, languages = { general = { hard_wrap_at = 100 } } })
  local buf = child:open_buffer({ filetype = 'lua', lines = { 'x = 1' } })

  child:format({ buf = buf })

  expect.equality(child:plugin_values().wrap.hard_wrap_at, 100)
  expect.equality(child:plugin_values().general.hard_wrap_at, 100)
end

T['general']['an Option that inherits keeps its own stored value'] = function()
  child:write_global({
    version = 1,
    languages = { general = { hard_wrap_at = 100 }, lua = { wrap = { hard_wrap_at = 80 } } },
  })
  local buf = child:open_buffer({ filetype = 'lua', lines = { 'x = 1' } })

  child:format({ buf = buf })

  expect.equality(child:plugin_values().wrap.hard_wrap_at, 80)
end

T['general']['an invalid general value warns, and inheriting Options use the general default'] = function()
  child:write_global({ version = 1, languages = { general = { hard_wrap_at = 0 } } })
  local buf = child:open_buffer({ filetype = 'lua', lines = { 'x = 1' } })

  child:format({ buf = buf })

  expect.equality(child:plugin_values().wrap.hard_wrap_at, 120)
  expect.equality(child:notices(), {
    {
      level = H.levels.WARN,
      message = 'codestyle: '
        .. child.paths.config
        .. '/codestyle.json: invalid values, their defaults are used: general.hard_wrap_at: 0 is out of range 1–1000',
    },
  })
end

T['refused plugin'] = MiniTest.new_set()

T['refused plugin']['its stored values are not checked'] = function()
  child:setup({ plugins = { 'codestyle-lua.nvim', 'codestyle-future-api.nvim' } })
  child:write_global({ version = 1, languages = { future = { spaces = { around_assignment = 'yes' } } } })
  local buf = child:open_buffer({ filetype = 'lua', lines = { 'x = 1' } })

  child:format({ buf = buf })

  expect.equality(child:lines(buf), { 'x=1' })
  expect.equality(child:notices(), {
    {
      level = H.levels.WARN,
      message = 'codestyle: codestyle-future-api.nvim is refused: it has the unknown api 2; the Core has api 1',
    },
  })
end

T['migrations'] = MiniTest.new_set()

T['migrations']['rename a key and a choice id on read'] = function()
  -- The fake plugin renamed spaces.assign to spaces.around_assignment, and the
  -- choice chop of wrap.call_arguments to chop_down.
  child:write_global({
    version = 1,
    languages = { lua = { spaces = { assign = true }, wrap = { call_arguments = 'chop' } } },
  })
  local buf = child:open_buffer({ filetype = 'lua', lines = { 'x=1' } })

  child:format({ buf = buf })

  expect.equality(child:lines(buf), { 'x = 1' })
  expect.equality(child:plugin_values().wrap.call_arguments, 'chop_down')
  expect.equality(child:notices(), {})
end

T['migrations']['never overwrite a new key that is set'] = function()
  child:write_global({
    version = 1,
    languages = { lua = { spaces = { assign = true, around_assignment = false } } },
  })
  local buf = child:open_buffer({ filetype = 'lua', lines = { 'x = 1' } })

  child:format({ buf = buf })

  expect.equality(child:lines(buf), { 'x=1' })
end

return T
