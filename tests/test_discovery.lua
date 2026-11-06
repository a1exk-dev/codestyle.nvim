-- Plugin discovery (ADR-0007, ADR-0003): installing a Language Plugin is
-- enough, and a broken or clashing plugin is refused with one clear warning.

local H = dofile('tests/helpers.lua')
local expect = MiniTest.expect

local child = H.new_child()

local T = MiniTest.new_set({
  hooks = {
    post_case = function()
      child:teardown()
    end,
  },
})

local spaces_around_assignment = {
  version = 1,
  languages = { lua = { spaces = { around_assignment = true } } },
}

T['a second plugin with an existing id is refused with one warning that names both'] = function()
  child:setup({ plugins = { 'codestyle-lua.nvim', 'codestyle-lua-clone.nvim' } })
  child:write_global(spaces_around_assignment)
  local buf = child:open_buffer({ filetype = 'lua', lines = { 'x=1' } })

  child:format({ buf = buf })
  child:format({ buf = buf })

  expect.equality(child:lines(buf), { 'x = 1' })
  expect.equality(child:notices(), {
    {
      level = H.levels.WARN,
      message = 'codestyle: codestyle-lua-clone.nvim is refused: its language id "lua" is already used by codestyle-lua.nvim',
    },
  })
end

T['a plugin with the reserved id general is refused with one warning'] = function()
  child:setup({ plugins = { 'codestyle-lua.nvim', 'codestyle-general.nvim' } })
  local buf = child:open_buffer({ filetype = 'general', lines = { 'x = 1' } })

  child:format({ buf = buf })

  expect.equality(child:lines(buf), { 'x = 1' })
  expect.equality(child:notices(), {
    {
      level = H.levels.WARN,
      message = 'codestyle: codestyle-general.nvim is refused: the language id "general" is reserved for the Core',
    },
    { level = H.levels.WARN, message = 'codestyle: no Language Plugin claims the filetype "general"' },
  })
end

T['a plugin with the previous api formats, with one deprecation warning'] = function()
  child:setup({ plugins = { 'codestyle-lua.nvim', 'codestyle-old-api.nvim' } })
  local buf = child:open_buffer({ filetype = 'oldapi', lines = { 'x = 1' } })

  child:format({ buf = buf })
  child:format({ buf = buf })

  expect.equality(child:lines(buf), { 'x=1' })
  expect.equality(child:notices(), {
    {
      level = H.levels.WARN,
      message = 'codestyle: codestyle-old-api.nvim has the deprecated api 0; it works for now, but update it to api 1',
    },
  })
end

T['a plugin with an unknown api is refused with one warning, and its stored values stay in the file'] = function()
  child:setup({ plugins = { 'codestyle-lua.nvim', 'codestyle-future-api.nvim' } })
  local stored = '{"version":1,"languages":{"future":{"spaces":{"around_assignment":true}}}}'
  child:write_global(stored)
  local buf = child:open_buffer({ filetype = 'future', lines = { 'x = 1' } })

  child:format({ buf = buf })
  child:format({ buf = buf })

  expect.equality(child:lines(buf), { 'x = 1' })
  expect.equality(child:notices(), {
    {
      level = H.levels.WARN,
      message = 'codestyle: codestyle-future-api.nvim is refused: it has the unknown api 2; the Core has api 1',
    },
  })
  expect.equality(child.fn.readfile(child.paths.config .. '/codestyle.json'), { stored })
end

T['a plugin that uses a missing plugin is listed but does not format, with one warning that names both'] = function()
  child:setup({ plugins = { 'codestyle-lua.nvim', 'codestyle-uses-missing.nvim' } })
  local buf = child:open_buffer({ filetype = 'usesmissing', lines = { 'x = 1' } })

  child:format({ buf = buf })
  child:format({ buf = buf })

  expect.equality(child:lines(buf), { 'x = 1' })
  expect.equality(child:notices(), {
    {
      level = H.levels.WARN,
      message = 'codestyle: codestyle-uses-missing.nvim does not format: '
        .. 'it uses the language "absent", which no installed plugin has',
    },
  })
end

T['a plugin that uses another export version is listed but does not format, with one warning that names both'] = function()
  child:setup({ plugins = { 'codestyle-lua.nvim', 'codestyle-uses-wrong.nvim' } })
  local buf = child:open_buffer({ filetype = 'useswrong', lines = { 'x = 1' } })

  child:format({ buf = buf })
  child:format({ buf = buf })

  expect.equality(child:lines(buf), { 'x = 1' })
  expect.equality(child:notices(), {
    {
      level = H.levels.WARN,
      message = 'codestyle: codestyle-uses-wrong.nvim does not format: '
        .. 'it uses version 2 of codestyle-lua.nvim, which exports version 1',
    },
  })
end

T['a spec that raises an error is refused with one warning, and the other plugins still format'] = function()
  child:setup({ plugins = { 'codestyle-spec-error.nvim', 'codestyle-lua.nvim' } })
  local buf = child:open_buffer({ filetype = 'lua', lines = { 'x = 1' } })

  child:format({ buf = buf })
  child:format({ buf = buf })

  expect.equality(child:lines(buf), { 'x=1' })
  local notices = child:notices()
  expect.equality(#notices, 1)
  expect.equality(notices[1].level, H.levels.WARN)
  expect.no_equality(
    notices[1].message:find(
      '^codestyle: codestyle%-spec%-error%.nvim is refused: its spec .*specerror%.lua does not load: .*this spec is broken'
    ),
    nil
  )
end

T['the formatter module is required on the first format, not on discovery'] = function()
  child:setup()
  local loaded = 'package.loaded["codestyle.languages.lua.formatter"] ~= nil'
  -- A format of an unclaimed buffer runs discovery.
  child:format({ buf = child:open_buffer({ filetype = 'text', lines = { 'x' } }) })
  local buf = child:open_buffer({ filetype = 'lua', lines = { 'x = 1' } })

  expect.equality(child.lua_get(loaded), false)

  child:format({ buf = buf })

  expect.equality(child.lua_get(loaded), true)
end

return T
