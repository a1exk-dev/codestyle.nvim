-- The Draft, Presets and saving (ADR-0006, ADR-0001, ADR-0003, ADR-0012):
-- tested through the Draft's interface, the files on disk and real buffers.

local H = dofile('tests/helpers.lua')
local expect = MiniTest.expect

local child = H.new_child()

local T = MiniTest.new_set({
  hooks = {
    pre_case = function()
      child:setup({ plugins = { 'codestyle-lua.nvim', 'codestyle-alt.nvim' } })
    end,
    post_case = function()
      child:teardown()
    end,
  },
})

--- Opens the Draft of a scope in the child as `_G.draft`.
---@param scope? 'global'|'project'
---@param root? string
---@return table? broken the broken file, when the Draft cannot open
local function open_draft(scope, root)
  return child.lua(
    [[
      local draft, broken = require('codestyle.instance').get().draft(...)
      _G.draft = draft
      return broken
    ]],
    { scope or 'global', root }
  )
end

--- Calls a Draft operation in the child and returns its results as a list.
---@param method string
---@return any[]
local function draft(method, ...)
  return child.lua('local method = ...; return { _G.draft[method](select(2, ...)) }', { method, ... })
end

--- A value of the Draft, as the Preview would format with it.
---@param id string
---@param key string dotted
local function value(id, key)
  return child.lua(
    'local id, key = ...; return vim.tbl_get(_G.draft.code_style().values(id), unpack(vim.split(key, ".", { plain = true })))',
    { id, key }
  )
end

---@param path string
---@return string?
local function read(path)
  local file = io.open(path, 'r')
  if not file then
    return nil
  end
  local text = file:read('*a')
  file:close()
  return text
end

---@return string?
local function global_file()
  return read(child.paths.config .. '/codestyle.json')
end

--- The Global file, decoded; it must exist.
---@return table
local function global_content()
  return vim.json.decode(assert(global_file()))
end

T['undo'] = MiniTest.new_set()

T['undo']['each set and reset is one step that undo and redo walk'] = function()
  open_draft()
  draft('set', 'lua', 'indent.size', 2)
  draft('set', 'lua', 'indent.size', 8)
  draft('reset', 'lua', 'indent.size')
  expect.equality(value('lua', 'indent.size'), 4)

  draft('undo')
  expect.equality(value('lua', 'indent.size'), 8)
  draft('undo')
  expect.equality(value('lua', 'indent.size'), 2)
  draft('redo')
  expect.equality(value('lua', 'indent.size'), 8)
  draft('undo')
  draft('undo')
  expect.equality(value('lua', 'indent.size'), 4)
  -- Nothing more to undo.
  expect.equality(draft('undo'), { false })
  expect.equality(value('lua', 'indent.size'), 4)
end

T['undo']['a new step after undo drops the steps that were undone'] = function()
  open_draft()
  draft('set', 'lua', 'indent.size', 2)
  draft('undo')
  draft('set', 'lua', 'comments.todo', 'FIXME')

  expect.equality(draft('redo'), { false })
  expect.equality(value('lua', 'indent.size'), 4)
  expect.equality(value('lua', 'comments.todo'), 'FIXME')
end

T['undo']['an invalid value is refused and leaves no step'] = function()
  open_draft()
  draft('set', 'lua', 'indent.size', 2)

  expect.equality(draft('set', 'lua', 'indent.size', 99), { false, '99 is out of range 0–32' })
  expect.equality(value('lua', 'indent.size'), 2)
  draft('undo')
  expect.equality(value('lua', 'indent.size'), 4)
end

T['undo']['save and discard clear the history'] = function()
  open_draft()
  draft('set', 'lua', 'indent.size', 2)
  expect.equality(draft('save'), { true })
  expect.equality(draft('undo'), { false })
  expect.equality(value('lua', 'indent.size'), 2)

  draft('set', 'lua', 'indent.size', 8)
  draft('discard')
  expect.equality(value('lua', 'indent.size'), 2)
  expect.equality(draft('undo'), { false })
  expect.equality(draft('redo'), { false })
end

T['undo']['observers hear every change'] = function()
  open_draft()
  child.lua([[
    _G.heard = 0
    _G.draft.subscribe(function() _G.heard = _G.heard + 1 end)
  ]])
  draft('set', 'lua', 'indent.size', 2)
  draft('undo')
  draft('redo')
  draft('discard')

  expect.equality(child.lua_get('_G.heard'), 4)
end

T['queries'] = MiniTest.new_set()

T['queries']['changed counts the values that differ from the default, and kept_languages the stored values without a plugin'] = function()
  child:write_global({
    version = 1,
    languages = {
      lua = { indent = { size = 99 }, comments = { todo = 'TODO' }, arrangement = { enabled = true } },
      php = { spaces = { around_assignment = true, before_paren = false }, wrap = 5 },
      css = vim.empty_dict(),
    },
  })
  open_draft()
  draft('set', 'lua', 'spaces.around_assignment', true)
  draft('set', 'lua', 'wrap.hard_wrap_at', 120)

  -- The invalid indent.size and the default comments.todo do not count; the Arrangement counts as one.
  expect.equality(draft('changed', 'lua'), { 3 })
  expect.equality(draft('changed', 'general'), { 0 })
  expect.equality(draft('kept_languages'), { { { id = 'css', count = 0 }, { id = 'php', count = 3 } } })
end

T['save'] = MiniTest.new_set()

T['save']['writes version and only the values that differ from the defaults, keys in a stable order'] = function()
  open_draft()
  draft('set', 'lua', 'spaces.around_assignment', true)
  draft('set', 'lua', 'indent.size', 4) -- the default
  draft('set', 'lua', 'names.globals', { 'vim', 'describe' })
  draft('set', 'lua', 'members.order', { 'fields', 'methods', 'metamethods' }) -- the default
  draft('set', 'lua', 'wrap.hard_wrap_at', 120) -- inherits: a set value is kept even when it equals General's
  draft('set', 'general', 'hard_wrap_at', 80)
  draft('set', 'alt', 'spaces.around_assignment', false) -- the default

  expect.equality(draft('save'), { true })

  expect.equality(
    global_file(),
    table.concat({
      '{',
      '  "version": 1,',
      '  "languages": {',
      '    "general": {',
      '      "hard_wrap_at": 80',
      '    },',
      '    "lua": {',
      '      "names": {',
      '        "globals": [',
      '          "vim",',
      '          "describe"',
      '        ]',
      '      },',
      '      "spaces": {',
      '        "around_assignment": true',
      '      },',
      '      "wrap": {',
      '        "hard_wrap_at": 120',
      '      }',
      '    }',
      '  }',
      '}',
      '',
    }, '\n')
  )
end

T['save']['an empty Code Style is the version alone'] = function()
  child:write_global({ version = 1, languages = { lua = { indent = { size = 4 } } } })
  open_draft()

  draft('save')

  expect.equality(global_file(), '{\n  "version": 1\n}\n')
end

T['save']['keeps unknown languages, unknown keys and unknown top-level keys'] = function()
  child:write_global(table.concat({
    '{"version": 1, "comment": "team style",',
    ' "languages": {',
    '  "php": {"spaces": {"around_assignment": false}, "list": [], "nothing": null, "empty": {}},',
    '  "lua": {"future": {"key": [1, 2]}, "spaces": {"around_assignment": false, "unknown": "x"}}',
    ' }}',
  }, '\n'))
  open_draft()
  draft('set', 'lua', 'indent.size', 2)

  draft('save')

  expect.equality(
    global_content(),
    vim.json.decode([[{"version": 1, "comment": "team style", "languages": {
      "php": {"spaces": {"around_assignment": false}, "list": [], "nothing": null, "empty": {}},
      "lua": {"future": {"key": [1, 2]}, "spaces": {"unknown": "x"}, "indent": {"size": 2}}}}]])
  )
  -- An empty list and an empty object keep their kind.
  local text = assert(global_file())
  expect.no_equality(text:find('"list": []', 1, true), nil)
  expect.no_equality(text:find('"empty": {}', 1, true), nil)
end

T['save']['writes migrated keys under their new names'] = function()
  child:write_global({
    version = 1,
    languages = { lua = { spaces = { assign = true }, wrap = { call_arguments = 'chop' } } },
  })
  open_draft()

  draft('save')

  expect.equality(global_content(), {
    version = 1,
    languages = { lua = { spaces = { around_assignment = true }, wrap = { call_arguments = 'chop_down' } } },
  })
end

T['save']['writes the Project file of the repo root'] = function()
  open_draft('project', child.paths.repo)
  draft('set', 'lua', 'indent.size', 2)

  draft('save')

  expect.equality(
    vim.json.decode(assert(read(child.paths.repo .. '/.codestyle.json'))),
    { version = 1, languages = { lua = { indent = { size = 2 } } } }
  )
  expect.equality(global_file(), nil)
end

T['save']['an invalid stored value stays in the file until its Option is set'] = function()
  child:write_global({ version = 1, languages = { lua = { indent = { size = 99 }, comments = { todo = 5 } } } })
  open_draft()
  -- Formatting and the Preview use the default.
  expect.equality(value('lua', 'indent.size'), 4)
  draft('set', 'lua', 'spaces.around_assignment', true)

  draft('save')
  expect.equality(
    global_content().languages.lua,
    { indent = { size = 99 }, comments = { todo = 5 }, spaces = { around_assignment = true } }
  )

  draft('set', 'lua', 'indent.size', 4)
  draft('reset', 'lua', 'comments.todo')
  draft('save')
  expect.equality(global_content().languages.lua, { spaces = { around_assignment = true } })
end

T['save']['an invalid stored Arrangement stays until the Arrangement is set or reset'] = function()
  local bad = { rules = 'not a list' }
  child:write_global({ version = 1, languages = { lua = { arrangement = bad }, alt = { arrangement = bad } } })
  open_draft()
  draft('set', 'lua', 'indent.size', 2)
  draft('save')
  expect.equality(global_content().languages, {
    lua = { arrangement = bad, indent = { size = 2 } },
    alt = { arrangement = bad },
  })

  draft('set_arrangement', 'lua', { enabled = true, rules = { { 'fields' } } })
  draft('reset_arrangement', 'alt')
  draft('save')
  expect.equality(global_content().languages, {
    lua = { arrangement = { enabled = true, rules = { { 'fields' } } }, indent = { size = 2 } },
  })

  -- Each Arrangement edit is one step.
  draft('set_arrangement', 'lua', { enabled = false })
  draft('undo')
  expect.equality(
    child.lua_get('_G.draft.code_style().raw().languages.lua.arrangement'),
    { enabled = true, rules = { { 'fields' } } }
  )
end

T['save']['a broken file opens no Draft'] = function()
  child:write_global('{ "version": 1,, }')

  local broken = assert(open_draft())

  expect.equality(broken.line, 1)
  expect.equality(child.lua_get('_G.draft'), vim.NIL)
end

T['save']['refuses to write over a file that broke after the Draft opened'] = function()
  open_draft()
  draft('set', 'lua', 'indent.size', 2)
  local path = child.paths.config .. '/codestyle.json'
  child:write_global('{\n  "version": 3\n}\n')

  local result = draft('save')

  expect.equality(result, {
    false,
    path .. ':2: unknown version 3, this Core reads version 1; fix or delete the file first',
  })
  expect.equality(global_file(), '{\n  "version": 3\n}\n')
  -- The history stays, so nothing is lost.
  expect.equality(draft('undo'), { true })
end

T['real buffers'] = MiniTest.new_set()

T['real buffers']['format with the saved Code Style while the Draft differs, and a save does not reformat them'] = function()
  local buf = child:open_buffer({ filetype = 'lua', lines = { 'x = 1' } })
  open_draft()
  draft('set', 'lua', 'spaces.around_assignment', true)

  child:format({ buf = buf })
  expect.equality(child:lines(buf), { 'x=1' })

  draft('save')
  expect.equality(child:lines(buf), { 'x=1' })

  child:format({ buf = buf })
  expect.equality(child:lines(buf), { 'x = 1' })
end

T['Presets'] = MiniTest.new_set()

--- The labels of the "Set from…" list of a language.
---@param id string
---@return string[]
local function preset_labels(id)
  return child.lua(
    [[return vim.tbl_map(function(preset) return preset.label end, require('codestyle.instance').get().presets.list(...))]],
    { id }
  )
end

--- Applies the Preset with this label of a language's list to the Draft.
---@param id string
---@param label string
local function apply_preset(id, label)
  child.lua(
    [[
      local id, label = ...
      local presets = require('codestyle.instance').get().presets
      for _, preset in ipairs(presets.list(id)) do
        if preset.label == label then
          return presets.apply(_G.draft, preset)
        end
      end
      error('no Preset ' .. label)
    ]],
    { id, label }
  )
end

T['Presets']['a Preset is one step that overwrites only its values, in general and another language too'] = function()
  open_draft()
  draft('set', 'lua', 'comments.todo', 'FIXME')
  draft('set', 'lua', 'indent.size', 8)

  apply_preset('lua', 'Roomy')

  expect.equality(value('lua', 'spaces.around_assignment'), true)
  expect.equality(value('lua', 'indent.size'), 2)
  expect.equality(value('lua', 'comments.todo'), 'FIXME')
  expect.equality(value('general', 'hard_wrap_at'), 100)
  expect.equality(value('alt', 'spaces.around_assignment'), true)
  expect.equality(child:notices(), {})

  draft('undo')
  expect.equality(value('lua', 'spaces.around_assignment'), false)
  expect.equality(value('lua', 'indent.size'), 8)
  expect.equality(value('general', 'hard_wrap_at'), 120)
  expect.equality(value('alt', 'spaces.around_assignment'), false)
end

T['Presets']['skips what it cannot apply, lists it in one notice and never touches Arrangement'] = function()
  child:write_global({ version = 1, languages = { lua = { arrangement = { enabled = true } } } })
  open_draft()

  apply_preset('lua', 'Mixed')

  expect.equality(value('lua', 'comments.todo'), 'XXX')
  expect.equality(value('alt', 'spaces.around_assignment'), false)
  expect.equality(child.lua_get('_G.draft.code_style().raw().languages.lua.arrangement'), { enabled = true })
  expect.equality(child.lua_get('_G.draft.code_style().raw().languages.c'), vim.NIL)
  expect.equality(child:notices(), {
    {
      level = H.levels.WARN,
      message = 'codestyle: Preset "Mixed" skipped 4 values: alt.spaces.around_assignment: expected a boolean, got "yes"; '
        .. 'c: Language Plugin not installed; lua.arrangement: Presets never set Arrangement; '
        .. 'lua.spaces.before_paren: no such Option',
    },
  })

  -- One step: undo takes back what did apply.
  draft('undo')
  expect.equality(value('lua', 'comments.todo'), 'TODO')
  -- Each apply tells again.
  apply_preset('lua', 'Mixed')
  expect.equality(#child:notices(), 2)
end

T['Presets']['user Presets from setup come after the plugin ones, marked (user), and a repeated name hides neither'] = function()
  child.lua([[require('codestyle').setup({
    presets = {
      { name = 'Roomy', language = 'lua', values = { lua = { indent = { size = 3 } } } },
      { name = 'Tight', language = 'alt', values = { alt = { spaces = { around_assignment = false } } } },
      { name = 'Narrow', language = 'general', values = { general = { hard_wrap_at = 60 } } },
    },
  })]])

  expect.equality(preset_labels('lua'), { 'Roomy', 'Mixed', 'Roomy (user)' })
  expect.equality(preset_labels('alt'), { 'Tight (user)' })
  expect.equality(preset_labels('general'), { 'Narrow (user)' })

  open_draft()
  apply_preset('lua', 'Roomy (user)')
  expect.equality(value('lua', 'indent.size'), 3)
  expect.equality(value('lua', 'spaces.around_assignment'), false)
end

return T
