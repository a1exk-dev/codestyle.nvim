-- Formatting a real buffer end to end (ADR-0014): a Code Style file, a buffer
-- in a fake language, an entry point, the lines read back.

local H = dofile('tests/helpers.lua')
local expect = MiniTest.expect

local child = H.new_child()

local T = MiniTest.new_set({
  hooks = {
    pre_case = function()
      child:setup({ plugins = { 'codestyle-lua.nvim', 'codestyle-broken.nvim' } })
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

T[':Codestyle format applies the Global Code Style'] = function()
  child:write_global(spaces_around_assignment)
  local buf = child:open_buffer({ filetype = 'lua', lines = { 'x=1' } })

  child.cmd('Codestyle format')

  expect.equality(child:lines(buf), { 'x = 1' })
end

T['format{} uses the plugin default when there is no Code Style file'] = function()
  -- The fake plugin's default for spaces.around_assignment is false.
  local buf = child:open_buffer({ filetype = 'lua', lines = { 'x = 1' } })

  child:format({ buf = buf })

  expect.equality(child:lines(buf), { 'x=1' })
end

T['one u restores the buffer, and an extmark on an untouched line keeps its place'] = function()
  child:write_global(spaces_around_assignment)
  local buf = child:open_buffer({ filetype = 'lua', lines = { 'x=1', '-- note', 'y=2' } })
  local ns = child.api.nvim_create_namespace('test')
  local mark = child.api.nvim_buf_set_extmark(buf, ns, 1, 3, {})

  child:format({ buf = buf })

  expect.equality(child:lines(buf), { 'x = 1', '-- note', 'y = 2' })
  expect.equality(child.api.nvim_buf_get_extmark_by_id(buf, ns, mark, {}), { 1, 3 })

  child.type_keys('u')

  expect.equality(child:lines(buf), { 'x=1', '-- note', 'y=2' })
end

T['a buffer whose filetype no plugin claims stays unchanged, with one WARN'] = function()
  child:write_global(spaces_around_assignment)
  local buf = child:open_buffer({ filetype = 'text', lines = { 'x=1' } })

  child.cmd('Codestyle format')

  expect.equality(child:lines(buf), { 'x=1' })
  expect.equality(child:notices(), {
    { level = H.levels.WARN, message = 'codestyle: no Language Plugin claims the filetype "text"' },
  })
end

T['a Language Plugin that raises leaves the buffer unchanged, with one ERROR'] = function()
  child:write_global({ version = 1, languages = { broken = { build = { raise = true } } } })
  local buf = child:open_buffer({ filetype = 'broken', lines = { 'x=1' } })

  child:format({ buf = buf })
  child.cmd('Codestyle format')

  expect.equality(child:lines(buf), { 'x=1' })
  local notices = child:notices()
  expect.equality(#notices, 2)
  for _, notice in ipairs(notices) do
    expect.equality(notice.level, H.levels.ERROR)
    expect.equality(
      vim.startswith(notice.message, 'codestyle: Language Plugin "broken" failed; the buffer is unchanged: '),
      true
    )
    expect.equality(notice.message:find('the fake broken plugin raises on purpose', 1, true) ~= nil, true)
  end
end

T[':Codestyle with an unknown subcommand gives one ERROR'] = function()
  child.cmd('Codestyle bogus')

  expect.equality(child:notices(), {
    { level = H.levels.ERROR, message = 'codestyle: unknown subcommand "bogus"' },
  })
end

return T
