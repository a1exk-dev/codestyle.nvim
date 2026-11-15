-- `codestyle.testing` (ADR-0013, ADR-0016, ADR-0011, ADR-0006): the run that
-- Language Plugin repos call over their vendored corpus and hand-written
-- cases. The fake `lua` plugin carries a tiny corpus in the layout of the
-- Research Corpus in `tests/fixtures/codestyle-lua.nvim/test/`. Tests call the
-- public `run{}` in a child and read its report; the exit status and the
-- bench script are checked on a real `nvim -l` process.

local H = dofile('tests/helpers.lua')
local expect = MiniTest.expect

local root = vim.fs.normalize(vim.fn.fnamemodify('.', ':p')):gsub('/$', '')
local lua_test = root .. '/tests/fixtures/codestyle-lua.nvim/test'

local child = H.new_child()

local T = MiniTest.new_set({
  hooks = {
    pre_case = function()
      child:setup({ plugins = { 'codestyle-lua.nvim', 'codestyle-stateful.nvim' } })
    end,
    post_case = function()
      child:teardown()
    end,
  },
})

--- Runs `codestyle.testing` in the child; default: the fake `lua` corpus and cases, nothing expected to fail.
---@param opts? table
---@return table report
local function run(opts)
  opts = vim.tbl_extend('force', {
    language = 'lua',
    corpus_dir = lua_test .. '/corpus',
    cases_dir = lua_test .. '/cases',
    expected_failures = {},
  }, opts or {})
  return child.lua("return require('codestyle.testing').run(...)", { opts })
end

--- The result of one case id.
---@param report table
---@param id string
---@return table
local function result(report, id)
  return vim.iter(report.results):find(function(each)
    return each.id == id
  end) or error('no result ' .. id .. ' in ' .. vim.inspect(report.results))
end

---@param report table
---@param id string
---@return string
local function verdict(report, id)
  return result(report, id).verdict
end

--- Writes a corpus record of the fake `lua` into a temporary corpus and returns the corpus folder.
---@param records table<string, table> key → record fields
---@return string
local function temp_corpus(records)
  local dir = child.paths.root .. '/corpus'
  for key, record in pairs(records) do
    child:write_file(
      ('%s/data/behavior/lua/%s.json'):format(dir, key),
      vim.tbl_extend('force', { key = key, language = 'lua', status = 'verified-effect' }, record)
    )
  end
  return dir
end

T['records'] = MiniTest.new_set()

T['records']['a matching record passes and a differing one fails'] = function()
  local report = run()

  expect.equality(verdict(report, 'ij_lua_space_around_assignment/Default/true/assign.lua'), 'pass')
  expect.equality(verdict(report, 'ij_lua_space_around_assignment/Default/false/body.lua'), 'pass')
  local failed = result(report, 'ij_lua_todo_marker/Default/FIXME/todo.lua')
  expect.equality(failed.verdict, 'fail')
  expect.equality(failed.message, 'the output differs:\n@@ -1 +1 @@\n--- FIXME: x\n+-- TODO: x\n')
  expect.equality(report.ok, false)
end

T['records']['translate scheme_xml_location and base settings to field addresses'] = function()
  local report = run()

  -- `common:INDENT.INDENT_SIZE` of the base is the address `indent:INDENT_SIZE`.
  expect.equality(verdict(report, 'ij_lua_space_around_assignment/indent_size = 2/true/body.lua'), 'pass')
  -- The fused `["tag:CCodeStyleSettings", "USE_DOUBLE_QUOTES"]` is `tag:CCodeStyleSettings:USE_DOUBLE_QUOTES`.
  expect.equality(verdict(report, 'ij_lua_double_quotes/Default/false/quotes.lua'), 'pass')
end

T['records']['Java marker regexes go through Regex Conversion'] = function()
  local report = run()

  -- `@fmt:(off|stop)` matches `@fmt:stop` only as a converted Vim regex.
  expect.equality(verdict(report, 'ij_formatter_off_tag/regex, spaces/@fmt:(off|stop)/markers.lua'), 'pass')
end

T['records']['formatter records run with Arrangement off'] = function()
  local report = run()

  -- The fake's default Arrangement is on and would move `M.a` above `M.b`.
  expect.equality(verdict(report, 'ij_lua_space_around_assignment/Default/true/module.lua'), 'pass')
end

T['records']['a left-out field and an untestable record are skipped'] = function()
  local report = run()

  local left_out = result(report, 'ij_lua_space_before_semicolon')
  expect.equality(left_out.verdict, 'skip')
  expect.equality(left_out.message, 'the field custom:SPACE_BEFORE_SEMICOLON is left out')
  expect.equality(result(report, 'ij_lua_wrap_on_typing').message, 'untestable-via-cli')
end

T['records']['a field that no Option reads fails'] = function()
  local corpus = temp_corpus({
    ij_lua_unknown = {
      scheme_xml_location = { 'custom', 'NO_SUCH_FIELD' },
      inputs = { ['a.lua'] = 'x=1\n' },
      base_outputs = { Default = { ['a.lua'] = 'x=1\n' } },
      results = { { base = 'Default', base_settings = {}, value = '1', internal = '1', changed_files = {} } },
    },
  })

  local report = run({ corpus_dir = corpus, cases_dir = child.paths.root .. '/none' })

  local failed = result(report, 'ij_lua_unknown/Default/1/a.lua')
  expect.equality(failed.verdict, 'fail')
  expect.equality(failed.message, 'no Option of an installed Language Plugin reads the field custom:NO_SUCH_FIELD')
end

T['expected failures'] = MiniTest.new_set()

T['expected failures']['a listed failure passes the run; a listed pass fails it'] = function()
  local report = run({
    expected_failures = {
      ['ij_lua_todo_marker/Default/FIXME/todo.lua'] = 'the fake ignores TODO markers',
      ['preset/Mixed'] = 'the fixture differs on purpose',
    },
  })
  expect.equality(verdict(report, 'ij_lua_todo_marker/Default/FIXME/todo.lua'), 'expected_failure')
  expect.equality(report.ok, true)

  report = run({
    expected_failures = {
      ['ij_lua_todo_marker/Default/FIXME/todo.lua'] = 'the fake ignores TODO markers',
      ['preset/Mixed'] = 'the fixture differs on purpose',
      ['case/assign'] = 'listed by mistake',
    },
  })
  local passed = result(report, 'case/assign')
  expect.equality(passed.verdict, 'unexpected_pass')
  expect.equality(passed.message, 'passes, but expected_failures lists it: listed by mistake')
  expect.equality(report.ok, false)
end

T['expected failures']['a listed id that no case has fails the run'] = function()
  local report = run({
    expected_failures = {
      ['ij_lua_todo_marker/Default/FIXME/todo.lua'] = 'the fake ignores TODO markers',
      ['preset/Mixed'] = 'the fixture differs on purpose',
      ['case/gone'] = 'an old case',
    },
  })

  expect.equality(result(report, 'case/gone').verdict, 'unexpected_pass')
  expect.equality(result(report, 'case/gone').message, 'no such case, but expected_failures lists it: an old case')
  expect.equality(report.ok, false)
end

T['expected failures']["a Flagged Option's records are expected to fail"] = function()
  local report = run()

  local failed = result(report, 'ij_lua_double_quotes/Default/true/quotes.lua')
  expect.equality(failed.verdict, 'expected_failure')
  expect.equality(failed.reason, 'flagged: escaped quotes differ from PhpStorm')
end

T['expected failures']['a Flagged Option whose records all pass fails the run'] = function()
  local corpus = temp_corpus({
    ij_lua_double_quotes = {
      scheme_xml_location = { 'tag:CCodeStyleSettings', 'USE_DOUBLE_QUOTES' },
      inputs = { ['a.lua'] = 'x=1\n' },
      base_outputs = { Default = { ['a.lua'] = 'x=1\n' } },
      results = { { base = 'Default', base_settings = {}, value = 'false', internal = 'false', changed_files = {} } },
    },
  })

  local report = run({ corpus_dir = corpus, cases_dir = child.paths.root .. '/none' })

  expect.equality(verdict(report, 'ij_lua_double_quotes/Default/false/a.lua'), 'pass')
  local stale = result(report, 'ij_lua_double_quotes')
  expect.equality(stale.verdict, 'unexpected_pass')
  expect.equality(
    stale.message,
    'every case passes, but the Option conversion.double_quotes is flagged: escaped quotes differ from PhpStorm'
  )
  expect.equality(report.ok, false)
end

T['cases'] = MiniTest.new_set()

T['cases']['case folders run with their codestyle.json and an optional range'] = function()
  local report = run()

  expect.equality(verdict(report, 'case/assign'), 'pass')
  expect.equality(verdict(report, 'case/range'), 'pass')
end

T['cases']['a case whose output differs fails'] = function()
  local cases = child.paths.root .. '/cases'
  child:write_file(cases .. '/wrong/input.lua', 'x=1\n')
  child:write_file(cases .. '/wrong/codestyle.json', '{}')
  child:write_file(cases .. '/wrong/output.lua', 'x = 1\n')

  local report = run({ corpus_dir = child.paths.root .. '/none', cases_dir = cases })

  expect.equality(result(report, 'case/wrong').message, 'the output differs:\n@@ -1 +1 @@\n-x = 1\n+x=1\n')
end

T['arrangement cases'] = MiniTest.new_set()

T['arrangement cases']['run alone: rearranged, not formatted, with the case rules or the default'] = function()
  local report = run()

  -- `M.a=1` keeps its spelling: a case only rearranges, as Rearrange Code.
  expect.equality(verdict(report, 'arrangement/lua/order/functions_first'), 'pass')
  -- `default` is the plugin's default Arrangement.
  expect.equality(verdict(report, 'arrangement/lua/order/default'), 'pass')
  -- A whole `<codeStyleSettings language="Lua">` block.
  expect.equality(verdict(report, 'arrangement/lua/order/block'), 'pass')
end

T['presets'] = MiniTest.new_set()

T['presets']['a Preset is checked against its presets.json diff; left-out fields are skipped'] = function()
  local report = run()

  local roomy = result(report, 'preset/Roomy')
  expect.equality(roomy.verdict, 'pass')
  expect.equality(roomy.skipped, {
    'Alt: no installed Language Plugin',
    'alt: Language Plugin not installed',
    'lua custom:SPACE_BEFORE_SEMICOLON: left out',
  })
  local mixed = result(report, 'preset/Mixed')
  expect.equality(mixed.verdict, 'fail')
  expect.equality(mixed.message, 'lua.comments.todo: the Preset sets "XXX", the scheme diff "YYY"')
end

T['run twice'] = MiniTest.new_set()

T['run twice']['a plugin that keeps state between calls fails'] = function()
  local stateful = root .. '/tests/fixtures/codestyle-stateful.nvim/test'

  local report = run({ language = 'stateful', corpus_dir = stateful .. '/corpus', cases_dir = stateful .. '/cases' })

  local failed = result(report, 'case/count')
  expect.equality(failed.verdict, 'fail')
  expect.equality(
    failed.message,
    'a second run gave another output, so the Language Plugin keeps state between runs:\n@@ -1 +1 @@\n--- run 1\n+-- run 2\n'
  )
end

T['exit status'] = MiniTest.new_set()

--- Runs a Lua script with `nvim -l`, with the Core and the fake plugins on the runtimepath.
---@param script string
---@param args? string[]
---@return vim.SystemCompleted
local function nvim_l(script, args)
  local env = {}
  for _, dir in ipairs({ 'config', 'data', 'state', 'cache' }) do
    env['XDG_' .. dir:upper() .. '_HOME'] = child.paths.root .. '/xdg/' .. dir
  end
  local cmd = { vim.v.progpath, '--headless', '-u', root .. '/tests/minimal_init.lua', '-l', script }
  return vim.system(vim.list_extend(cmd, args or {}), { env = env, text = true, cwd = root }):wait()
end

T['exit status']['is zero when every result is expected, and non-zero on any unexpected one'] = function()
  local done = nvim_l(lua_test .. '/run.lua')
  expect.equality(done.code, 0)
  expect.equality(done.stdout:find('codestyle.testing lua: ', 1, true) ~= nil, true)

  local script = child.paths.root .. '/run.lua'
  child:write_file(
    script,
    ([[
      vim.opt.runtimepath:append(%q)
      require('codestyle.testing').main({ language = 'lua', corpus_dir = %q, cases_dir = %q, expected_failures = {} })
    ]]):format(root .. '/tests/fixtures/codestyle-lua.nvim', lua_test .. '/corpus', lua_test .. '/cases')
  )
  done = nvim_l(script)
  expect.equality(done.code, 1)
  expect.equality(done.stdout:find('FAIL ij_lua_todo_marker/Default/FIXME/todo.lua', 1, true) ~= nil, true)
end

T['bench'] = MiniTest.new_set()

T['bench']['prints a time per step for each installed plugin sample'] = function()
  local done = nvim_l(root .. '/bench/run.lua', { root .. '/tests/fixtures/codestyle-lua.nvim' })

  expect.equality(done.code, 0)
  -- A smoke test: the lines are there, the numbers are not checked.
  expect.equality(done.stdout:match('lua Spaces%s+engine%s+[%d.]+ ms') ~= nil, true)
  expect.equality(done.stdout:match('lua Wrapping%s+total%s+[%d.]+ ms') ~= nil, true)
end

return T
