-- Arrangement in format runs (ADR-0011, ADR-0018, ADR-0002). The fake `lua`
-- entries are the members of the module table that the chunk returns. Every
-- case formats a real buffer through the public `format{}` or `:Codestyle`.

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

--- The lua values of every case: spaces around `=`, so formatting shows.
---@param arrangement? table
---@return table
local function lua(arrangement)
  return { spaces = { around_assignment = true }, arrangement = arrangement }
end

---@param languages table
local function global(languages)
  child:write_global({ version = 1, languages = languages })
end

---@param lines string[]
---@param opts? { range?: integer[], name?: string, filetype?: string, arrangement?: string }
---@return string[]
local function format(lines, opts)
  opts = opts or {}
  local buf = child:open_buffer({ filetype = opts.filetype or 'lua', lines = lines, name = opts.name })
  child:format({ buf = buf, range = opts.range, arrangement = opts.arrangement })
  return child:lines(buf)
end

--- A module whose members `format` rearranges.
---@param members string[]
---@return string[]
local function module(members)
  return vim.list_extend(vim.list_extend({ 'local M = {}', '' }, members), { '', 'return M' })
end

---@param slots table
---@param extra? table
---@return table
local function rules(slots, extra)
  return vim.tbl_extend('force', { keep_together = {}, slots = slots }, extra or {})
end

T['rules'] = MiniTest.new_set()

T['rules']['Slots order the entries; keep keeps their source order; unmatched entries go last'] = function()
  global({ lua = lua(rules({ { { is = { 'method' } } }, { { is = { 'field' } } } })) })

  local lines = format(module({ 'M.b=1', 'function M.run() end', 'function M:go() end', 'M.a=2' }))

  expect.equality(lines, module({ 'function M:go() end', '', 'M.b = 1', 'M.a = 2', '', 'function M.run() end' }))
  expect.equality(child:notices(), {})
end

T['rules']['by_name sorts a rule by name; the rule of the highest priority takes an entry'] = function()
  global({
    lua = lua(rules({
      { { is = { 'function' }, order = 'by_name' } },
      -- More atoms than the rule above, so it takes `_hidden` first.
      { { is = { 'function', 'private' } } },
    })),
  })

  local lines = format(module({ 'function M.c() end', 'function M._hidden() end', 'function M.a() end' }))

  expect.equality(lines, module({ 'function M.a() end', '', 'function M.c() end', '', 'function M._hidden() end' }))
end

T['rules']['an alias expands into its rules, each joined with the rule'] = function()
  global({
    lua = lua(rules({ { { is = { 'function' }, alias = 'visibility' } }, { { is = { 'field' } } } }, {
      aliases = { visibility = { { is_not = { 'private' } }, { is = { 'private' } } } },
    })),
  })

  local lines = format(module({ 'M.x=1', 'function M._b() end', 'function M.a() end' }))

  expect.equality(lines, module({ 'function M.a() end', '', 'function M._b() end', '', 'M.x = 1' }))
end

T['rules']['name and namespace are full, case-sensitive Vim regexes'] = function()
  global({
    lua = lua(rules({
      { { name = 'get.*' } },
      { { namespace = 'm', is = { 'field' } } },
      { { namespace = 'M', is = { 'field' } } },
    })),
  })

  local lines = format(module({ 'function M.forget() end', 'M.x=1', 'function M.Get() end', 'function M.get_a() end' }))

  expect.equality(
    lines,
    module({ 'function M.get_a() end', '', 'M.x = 1', '', 'function M.forget() end', '', 'function M.Get() end' })
  )
end

T['keep together'] = MiniTest.new_set()

T['keep together']['a getter and its setter stay together in the slot of the getter'] = function()
  global({ lua = lua(rules({ { { is = { 'field' } } } }, { keep_together = { { kind = 'getters_setters' } } })) })

  local lines = format(module({
    'function M.set_x() end',
    'function M.other() end',
    'function M.get_x() end',
    'M.x=1',
  }))

  expect.equality(
    lines,
    -- `other` and `get_x` keep their places, and so the gap between them.
    module({ 'M.x = 1', '', 'function M.other() end', 'function M.get_x() end', '', 'function M.set_x() end' })
  )
end

T['keep together']['dependent methods follow their caller depth-first or breadth-first'] = function()
  local members = {
    'function M.q1() end',
    'function M.p() M.p1() M.p2() end',
    'function M.root() M.p() M.q() end',
    'function M.p1() end',
    'function M.q() M.q1() end',
    'function M.p2() end',
  }
  local function arranged(order)
    global({ lua = lua(rules({}, { keep_together = { { kind = 'dependent_methods', order = order } } })) })
    local lines = format(module(members))
    return vim.tbl_map(
      function(line)
        return line:match('^function M%.(%w+)')
      end,
      vim.tbl_filter(function(line)
        return line:match('^function') ~= nil
      end, lines)
    )
  end

  expect.equality(arranged('depth_first'), { 'root', 'p', 'p1', 'p2', 'q', 'q1' })
  expect.equality(arranged('breadth_first'), { 'root', 'p', 'q', 'p1', 'p2', 'q1' })
end

T['keep together']['doc comments and a comment on the last line travel; other comments stay'] = function()
  global({ lua = lua(rules({ { { is = { 'function' } } }, { { is = { 'field' } } } })) })

  local lines = format(module({
    '--- The x.',
    'M.x=1 -- one',
    '-- stays',
    'function M.f() end',
  }))

  expect.equality(lines, module({ 'function M.f() end', '-- stays', '--- The x.', 'M.x = 1 -- one' }))
end

T['runs'] = MiniTest.new_set()

T['runs']['by default a run rearranges first and formats the moved code'] = function()
  global({ lua = lua() })

  local lines = format(module({ 'function M.f() end', 'M.x=1' }))

  expect.equality(lines, module({ 'M.x = 1', '', 'function M.f() end' }))
end

T['runs']['with enabled = false a run does not rearrange, and :Codestyle arrange does'] = function()
  global({ lua = lua({ enabled = false }) })
  local buf = child:open_buffer({ filetype = 'lua', lines = module({ 'function M.f() end', 'M.x=1' }) })

  child:format({ buf = buf })
  expect.equality(child:lines(buf), module({ 'function M.f() end', 'M.x = 1' }))

  child.cmd('Codestyle arrange')
  expect.equality(child:lines(buf), module({ 'M.x = 1', '', 'function M.f() end' }))
end

T['runs']['a range rearranges only the entries it touches, among themselves'] = function()
  global({ lua = lua(rules({ { { is = { 'field' }, order = 'by_name' } } })) })

  -- Lines 4 and 5 are `M.c` and `M.b`; `M.d` and `M.a` stay.
  local lines = format(module({ 'M.d=4', 'M.c=3', 'M.b=2', 'M.a=1' }), { range = { 4, 5 } })

  expect.equality(lines, module({ 'M.d=4', 'M.b = 2', 'M.c = 3', 'M.a=1' }))
end

T['runs']['Arrangement ignores formatter markers'] = function()
  global({ lua = lua(rules({ { { is = { 'field' }, order = 'by_name' } } })) })

  local lines = format(module({ '-- @formatter:off', 'M.b=2', 'M.a=1', '-- @formatter:on' }))

  expect.equality(lines, module({ '-- @formatter:off', 'M.a=1', 'M.b=2', '-- @formatter:on' }))
end

T['runs']['a file that Do not format matches is not rearranged'] = function()
  global({ general = { do_not_format = { '*.lua' } }, lua = lua() })

  local lines = format(module({ 'function M.f() end', 'M.x=1' }), { name = child.paths.repo .. '/a.lua' })

  expect.equality(lines, module({ 'function M.f() end', 'M.x=1' }))
end

T['runs']['an embedded part uses its own Arrangement and enabled; entries never cross it'] = function()
  local fences = {
    '```lua',
    'local M = {}',
    'function M.f() end',
    'M.b=2',
    'return M',
    '```',
    '',
    '```lua',
    'local M = {}',
    'M.a=1',
    'function M.g() end',
    'return M',
    '```',
    '',
  }
  global({ lua = lua() })
  expect.equality(format(fences, { filetype = 'markdown' }), {
    '```lua',
    'local M = {}',
    'M.b = 2',
    '',
    'function M.f() end',
    'return M',
    '```',
    '',
    '```lua',
    'local M = {}',
    'M.a = 1',
    'function M.g() end',
    'return M',
    '```',
    '',
  })

  global({ lua = lua({ enabled = false }) })
  local lines = format(fences, { filetype = 'markdown' })
  expect.equality(lines[3], 'function M.f() end')
end

T['runs']['an invalid stored Arrangement uses the whole default, with one warning naming the bad part'] = function()
  global({ lua = lua({ enabled = true, slots = { { { is = { 'fild' } } } } }) })

  local lines = format(module({ 'function M.f() end', 'M.x=1' }))
  format(module({ 'M.y=1' }))

  expect.equality(lines, module({ 'M.x = 1', '', 'function M.f() end' }))
  local path = child.paths.config .. '/codestyle.json'
  expect.equality(child:notices(), {
    {
      level = H.levels.WARN,
      message = ('codestyle: %s: invalid values, their defaults are used: '):format(path)
        .. 'lua.arrangement.slots[1][1].is: unknown token "fild"; the whole default Arrangement is used',
    },
  })
end

T['runs']['saving drops an Arrangement that equals the default'] = function()
  global({ lua = { arrangement = { enabled = false } } })
  child.lua([[_G.draft = require('codestyle.instance').get().draft('global')]])

  child.lua([[_G.draft.set_arrangement('lua', { enabled = true })]])
  child.lua([[_G.draft.save()]])

  local file = assert(io.open(child.paths.config .. '/codestyle.json'))
  local content = vim.json.decode(file:read('*a'))
  file:close()
  expect.equality(content, { version = 1 })
end

T['runs']['the run returns the Slot and rule of each entry, at its row in the result'] = function()
  global({ lua = lua(rules({ { { is = { 'method' } }, { is = { 'field' } } } })) })

  local matches = child.lua(
    [[
    local instance = require('codestyle.instance').get()
    local code_style = instance.draft('global').code_style()
    return instance.format_run.run({
      lines = ...,
      language = 'lua',
      parser = 'lua',
      code_style = code_style,
    }).matches
  ]],
    { module({ 'function M.f() end', 'M.x=1', 'function M:m() end' }) }
  )

  -- Result: M:m (row 2), a blank line, M.x (row 4), a blank line, M.f (row 6), which no rule matched.
  -- Each match also gives where its entry ends after formatting (`M.x = 1`).
  expect.equality(matches, {
    { language = 'lua', row = 2, col = 0, end_row = 2, end_col = 18, slot = 1, rule = 1 },
    { language = 'lua', row = 4, col = 0, end_row = 4, end_col = 7, slot = 1, rule = 2 },
    { language = 'lua', row = 6, col = 0, end_row = 6, end_col = 18 },
  })
end

T['overridden'] = MiniTest.new_set()

--- Starts a fake LSP client for the buffer. It answers `typeHierarchy/supertypes`
--- with the parent `Base` and `textDocument/documentSymbol` with its member `b`,
--- after `delay` ms. With `hierarchy = false` it answers type hierarchy requests
--- with MethodNotFound, as a server without them does.
---@param buf integer
---@param opts { delay?: integer, hierarchy?: boolean }
local function fake_lsp(buf, opts)
  child.lua(
    [[
      local buf, delay, hierarchy = ...
      vim.lsp.start({
        name = 'fake_hierarchy',
        cmd = function()
          local closing = false
          return {
            request = function(method, _, callback)
              local answers = {
                initialize = {
                  capabilities = { typeHierarchyProvider = hierarchy, documentSymbolProvider = true },
                },
                ['typeHierarchy/supertypes'] = { { name = 'Base', kind = 5, uri = 'file:///base.lua' } },
                ['textDocument/documentSymbol'] = { { name = 'b', kind = 12 } },
              }
              if method == 'initialize' or method == 'shutdown' then
                callback(nil, answers[method])
              elseif not hierarchy and vim.startswith(method, 'typeHierarchy/') then
                callback({ code = -32601, message = 'Unhandled method ' .. method }, nil)
              else
                vim.defer_fn(function()
                  callback(nil, answers[method])
                end, delay)
              end
              return true, 1
            end,
            notify = function() return true end,
            is_closing = function() return closing end,
            terminate = function() closing = true end,
          }
        end,
      }, { bufnr = buf })
      vim.wait(1000, function()
        return #vim.lsp.get_clients({ bufnr = buf }) > 0
      end)
    ]],
    { buf, opts.delay or 0, opts.hierarchy ~= false }
  )
end

local overridden_first = rules({ { { is = { 'overridden' } } } })
local members = { 'function M.a() end', 'function M.b() end' }

---@param buf integer
---@return string[]
local function functions(buf)
  return vim.tbl_filter(function(line)
    return line:match('^function') ~= nil
  end, child:lines(buf))
end

T['overridden']['with no LSP client it matches nothing, with one warning per run'] = function()
  global({ lua = lua(overridden_first) })
  local buf = child:open_buffer({ filetype = 'lua', lines = module(members) })

  child:format({ buf = buf })
  child:format({ buf = buf })

  expect.equality(functions(buf), members)
  local warning = {
    level = H.levels.WARN,
    message = 'codestyle: Arrangement of "lua" needs the LSP (typeHierarchy/supertypes), but no LSP client is '
      .. 'attached to the buffer; "overridden" matches nothing',
  }
  expect.equality(child:notices(), { warning, warning })
end

T['overridden']['a client that answers typeHierarchy/supertypes makes it match'] = function()
  global({ lua = lua(overridden_first) })
  local buf = child:open_buffer({ filetype = 'lua', lines = module(members) })
  fake_lsp(buf, {})

  child:format({ buf = buf })

  expect.equality(functions(buf), { 'function M.b() end', 'function M.a() end' })
  expect.equality(child:notices(), {})
end

T['overridden']['a client that does not support the method matches nothing, with one warning'] = function()
  global({ lua = lua(overridden_first) })
  local buf = child:open_buffer({ filetype = 'lua', lines = module(members) })
  fake_lsp(buf, { hierarchy = false })

  child:format({ buf = buf })

  expect.equality(functions(buf), members)
  expect.equality(child:notices(), {
    {
      level = H.levels.WARN,
      message = 'codestyle: Arrangement of "lua" needs the LSP (typeHierarchy/supertypes), but no LSP client of '
        .. 'the buffer supports it; "overridden" matches nothing',
    },
  })
end

T['overridden']['the time budget of a run is 1000 ms (temporary default of the named seam)'] = function()
  global({ lua = lua(overridden_first) })
  local buf = child:open_buffer({ filetype = 'lua', lines = module(members) })
  -- Both requests together take 2 × 350 ms: within the budget.
  fake_lsp(buf, { delay = 350 })
  child:format({ buf = buf })
  expect.equality(functions(buf), { 'function M.b() end', 'function M.a() end' })
  expect.equality(child:notices(), {})

  -- Together 2 × 650 ms: the second request times out.
  child.lua('vim.lsp.stop_client(vim.lsp.get_clients())')
  local slow = child:open_buffer({ filetype = 'lua', lines = module(members) })
  fake_lsp(slow, { delay = 650 })
  child:format({ buf = slow })
  expect.equality(functions(slow), members)
  expect.equality(child:notices(), {
    {
      level = H.levels.WARN,
      message = 'codestyle: Arrangement of "lua" needs the LSP (textDocument/documentSymbol), but it gave no '
        .. 'answer within 1000 ms; "overridden" matches nothing',
    },
  })
end

return T
