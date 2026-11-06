-- `codestyle.testing` (ADR-0013, ADR-0016): the run that a Language Plugin
-- repo calls from `test/run.lua` over its vendored Research Corpus and its
-- hand-written cases. It is public and versioned with `api`. An unexpected
-- failure fails the run, and so does an unexpected pass, so the list of
-- expected failures only shrinks. The records of a Flagged Option are
-- expected to fail. Every formatting check runs twice (ADR-0016).
--
--   require('codestyle.testing').main({
--     language = 'php',
--     corpus_dir = 'test/corpus',
--     cases_dir = 'test/cases',
--     expected_failures = dofile('test/expected_failures.lua'),
--   })

local checks_of = require('codestyle.testing.checks')
local corpus = require('codestyle.testing.corpus')

---@alias codestyle.testing.Verdict
---| 'pass' the check passed and was not expected to fail
---| 'fail' an unexpected failure
---| 'expected_failure' a failure that `expected_failures` lists, or of a Flagged Option's record
---| 'unexpected_pass' a listed check that passes, a listed id that no check has, or a Flagged Option whose checks all pass
---| 'skip' not run: untestable, left out, or an `.editorconfig` field

--- The result of one case id.
---@class codestyle.testing.Result
---@field id string
---@field verdict codestyle.testing.Verdict
---@field message? string why it failed, passed unexpectedly or was skipped
---@field reason? string why it is expected to fail
---@field skipped? string[] for a Preset: the values that one side leaves out

---@class codestyle.testing.Counts
---@field pass integer
---@field fail integer
---@field expected_failure integer
---@field unexpected_pass integer
---@field skip integer

---@class codestyle.testing.Report
---@field language string
---@field ok boolean true when no result is unexpected and the run could start
---@field error? string why the run could not start
---@field results codestyle.testing.Result[] records, Arrangement cases, Presets, hand-written cases, then stale listed ids
---@field counts codestyle.testing.Counts
---@field notices string[] what the Core reported while it loaded the plugins

---@class codestyle.testing.Opts
---@field language string the language id of the tested plugin
---@field corpus_dir? string the vendored Research Corpus, `test/corpus`
---@field cases_dir? string the hand-written cases, `test/cases`
---@field expected_failures? table<string, string> case id → reason

local M = {}

---@param results codestyle.testing.Result[]
---@return codestyle.testing.Counts
local function count(results)
  local counts = { pass = 0, fail = 0, expected_failure = 0, unexpected_pass = 0, skip = 0 }
  for _, result in ipairs(results) do
    counts[result.verdict] = counts[result.verdict] + 1
  end
  return counts
end

---@param registry codestyle.Registry
---@param language string
---@return string? parser
---@return string? problem
local function parser_of(registry, language)
  local status = registry.status(language)
  if not status then
    return nil, ('no installed Language Plugin has the language id "%s"'):format(language)
  elseif status.kind == 'refused' or status.kind == 'formatting_off' then
    return nil, ('the Language Plugin of "%s" is not used: %s'):format(language, status.reason)
  end
  local parsers = (registry.get(language) --[[@as codestyle.Spec]]).parsers.default or {}
  for _, parser in ipairs(parsers) do
    if vim.treesitter.language.add(parser) then
      return parser
    end
  end
  return nil, ('no parser of "%s" is installed: %s'):format(language, table.concat(parsers, ', '))
end

--- Runs the checks and returns the report. It changes no file.
---@param opts codestyle.testing.Opts
---@return codestyle.testing.Report
function M.run(opts)
  local messages = {} ---@type string[]
  local notices = require('codestyle.notices').new({
    notify = function(message)
      table.insert(messages, message)
    end,
  })
  local registry = require('codestyle.registry').new({ notices = notices, api = require('codestyle').api })
  ---@type codestyle.testing.Report
  local report = { language = opts.language, ok = false, results = {}, counts = count({}), notices = messages }

  local parser, problem = parser_of(registry, opts.language)
  if not parser then
    report.error = problem
    return report
  end
  local checks = checks_of.new({
    registry = registry,
    format_run = require('codestyle.format_run').new({ registry = registry }),
    importer = require('codestyle.scheme_xml.importer').new({ registry = registry }),
    presets = require('codestyle.presets').new({
      registry = registry,
      notices = notices,
      settings = function()
        return {}
      end,
    }),
    language = opts.language,
    parser = parser,
  })

  local all = {} ---@type codestyle.testing.Check[]
  if opts.corpus_dir then
    vim.list_extend(all, checks.records(corpus.records(opts.corpus_dir), opts.corpus_dir))
    vim.list_extend(all, checks.arrangement(corpus.arrangement_cases(opts.corpus_dir)))
    vim.list_extend(all, checks.presets(corpus.presets(opts.corpus_dir)))
  end
  if opts.cases_dir then
    vim.list_extend(all, checks.cases(corpus.cases(opts.cases_dir)))
  end

  local listed = opts.expected_failures or {}
  local seen = {} ---@type table<string, true>
  ---@type table<string, { flagged: { key: string, reason: string }, failed: boolean }>
  local flagged_records = {}
  local results = report.results
  for _, check in ipairs(all) do
    seen[check.id] = true
    local outcome = check.run()
    ---@type codestyle.testing.Result
    local result = { id = check.id, verdict = outcome.status, message = outcome.message, skipped = outcome.skipped }
    local reason = listed[check.id] ---@type string?
    if not reason and check.flagged then
      reason = 'flagged: ' .. check.flagged.reason
      local record = flagged_records[check.flagged.record] or { flagged = check.flagged, failed = false }
      flagged_records[check.flagged.record] = record
      record.failed = record.failed or outcome.status == 'fail'
      if outcome.status == 'pass' then
        reason = nil
      end
    end
    if reason and outcome.status == 'fail' then
      result.verdict, result.reason = 'expected_failure', reason
    elseif reason and outcome.status == 'pass' then
      result.verdict, result.reason = 'unexpected_pass', reason
      result.message = 'passes, but expected_failures lists it: ' .. reason
    end
    table.insert(results, result)
  end
  local records = vim.tbl_keys(flagged_records)
  table.sort(records)
  for _, id in ipairs(records) do
    local record = flagged_records[id]
    if not record.failed then
      table.insert(results, {
        id = id,
        verdict = 'unexpected_pass',
        message = ('every case passes, but the Option %s is flagged: %s'):format(
          record.flagged.key,
          record.flagged.reason
        ),
      })
    end
  end
  local stale = vim.tbl_keys(listed)
  table.sort(stale)
  for _, id in ipairs(stale) do
    if not seen[id] then
      table.insert(results, {
        id = id,
        verdict = 'unexpected_pass',
        reason = listed[id],
        message = 'no such case, but expected_failures lists it: ' .. listed[id],
      })
    end
  end

  report.counts = count(results)
  report.ok = report.counts.fail == 0 and report.counts.unexpected_pass == 0
  return report
end

--- The report as text: each unexpected result, then one line of totals.
---@param report codestyle.testing.Report
---@return string
function M.format(report)
  local lines = {} ---@type string[]
  for _, message in ipairs(report.notices) do
    table.insert(lines, message)
  end
  if report.error then
    table.insert(lines, ('ERROR codestyle.testing %s: %s'):format(report.language, report.error))
    return table.concat(lines, '\n') .. '\n'
  end
  for _, result in ipairs(report.results) do
    if result.verdict == 'fail' then
      table.insert(lines, ('FAIL %s: %s'):format(result.id, result.message))
    elseif result.verdict == 'unexpected_pass' then
      table.insert(lines, ('UNEXPECTED PASS %s: %s'):format(result.id, result.message))
    end
  end
  local counts = report.counts
  table.insert(
    lines,
    ('codestyle.testing %s: %d passed, %d failed, %d expected failures, %d unexpected passes, %d skipped'):format(
      report.language,
      counts.pass,
      counts.fail,
      counts.expected_failure,
      counts.unexpected_pass,
      counts.skip
    )
  )
  return table.concat(lines, '\n') .. '\n'
end

--- Runs the checks, prints the report and exits Neovim: status 0 when every result is
--- expected, else 1. For `nvim --headless -l test/run.lua`.
---@param opts codestyle.testing.Opts
function M.main(opts)
  local report = M.run(opts)
  io.stdout:write(M.format(report))
  io.stdout:flush()
  os.exit(report.ok and 0 or 1)
end

return M
