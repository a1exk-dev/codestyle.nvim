-- The files of a Language Plugin's tests (ADR-0013): the vendored Research
-- Corpus in its own layout (`data/behavior/<slug>/<key>.json`,
-- `tests/gui/arrangement/<lang>/<topic>/<case>/`, `data/presets.json`) and the
-- hand-written `test/cases/<name>/`. A missing folder or file means nothing
-- to run. A file that does not read raises: the corpus is never edited by hand.

local M = {}

--- A file of a Behaviour Record's results, by name.
---@class codestyle.testing.ChangedFile
---@field output string

--- One value of a Behaviour Record on one base.
---@class codestyle.testing.RecordResult
---@field base string
---@field base_settings table<string, string> corpus spelling → scheme-XML value
---@field value string the `.editorconfig` spelling, part of the case id
---@field internal string the scheme-XML spelling
---@field changed_files table<string, codestyle.testing.ChangedFile>

--- A formatter Behaviour Record.
---@class codestyle.testing.Record
---@field key string
---@field scheme_xml_location string[]
---@field status string `verified-effect`, `no-visible-effect` or `untestable-via-cli`
---@field inputs table<string, string>
---@field base_outputs table<string, table<string, string>>
---@field results codestyle.testing.RecordResult[]

--- An Arrangement case folder.
---@class codestyle.testing.ArrangementCase
---@field name string its path below `tests/gui/arrangement/`, such as `php/order/mixed_vis`
---@field xml string `arrangement.xml`, trimmed
---@field input string
---@field input_path string
---@field output string

--- A Preset of `presets.json`.
---@class codestyle.testing.CorpusPreset
---@field name string
---@field scheme_xml_diff string

--- A hand-written case folder.
---@class codestyle.testing.HandCase
---@field name string
---@field dir string
---@field input string
---@field input_path string
---@field output? string nil when the folder has no `output.*`
---@field codestyle string the text of `codestyle.json`, or `{}` without one
---@field range? string the text of `range`

---@param path string
---@return string?
local function read(path)
  local file = io.open(path, 'rb')
  if not file then
    return nil
  end
  local text = file:read('*a')
  file:close()
  return text
end

---@param path string
---@return any
local function read_json(path)
  local ok, value = pcall(vim.json.decode, read(path) or '', { luanil = { object = true, array = true } })
  if not ok then
    error(('%s is not valid JSON: %s'):format(path, value), 0)
  end
  return value
end

---@param dir string
---@param pattern string
---@return string[]
local function glob(dir, pattern)
  local found = vim.fn.globpath(dir, pattern, false, true)
  table.sort(found)
  return found
end

--- The formatter records, by folder and key.
---@param corpus string
---@return codestyle.testing.Record[]
function M.records(corpus)
  local records = {}
  for _, path in ipairs(glob(corpus, 'data/behavior/*/*.json')) do
    local folder = vim.fs.basename(vim.fs.dirname(path))
    if vim.fs.basename(path) ~= 'index.json' and not folder:match('^_') then
      local record = read_json(path)
      if type(record) == 'table' and record.record_type ~= 'arrangement' and record.results then
        table.insert(records, record)
      end
    end
  end
  return records
end

--- The Arrangement cases, by path.
---@param corpus string
---@return codestyle.testing.ArrangementCase[]
function M.arrangement_cases(corpus)
  local cases = {}
  local base = vim.fs.joinpath(corpus, 'tests/gui/arrangement')
  for _, path in ipairs(glob(base, '**/arrangement.xml')) do
    local dir = vim.fs.dirname(path)
    local input = glob(dir, 'input.*')[1]
    local output = glob(dir, 'output.*')[1]
    if input and output then
      table.insert(cases, {
        name = vim.fs.relpath(base, dir) --[[@as string]],
        xml = vim.trim(read(path) or ''),
        input = read(input) or '',
        input_path = input,
        output = read(output) or '',
      })
    end
  end
  return cases
end

--- The Presets of `presets.json`, by name.
---@param corpus string
---@return codestyle.testing.CorpusPreset[]
function M.presets(corpus)
  local path = vim.fs.joinpath(corpus, 'data/presets.json')
  if not vim.uv.fs_stat(path) then
    return {}
  end
  local presets = vim.tbl_values(read_json(path).presets or {})
  table.sort(presets, function(a, b)
    return a.name < b.name
  end)
  return presets
end

--- The hand-written cases, by name.
---@param cases_dir string
---@return codestyle.testing.HandCase[]
function M.cases(cases_dir)
  local cases = {}
  for _, input in ipairs(glob(cases_dir, '*/input.*')) do
    local dir = vim.fs.dirname(input)
    local output = glob(dir, 'output.*')[1]
    table.insert(cases, {
      name = vim.fs.basename(dir),
      dir = dir,
      input = read(input) or '',
      input_path = input,
      output = output and read(output),
      codestyle = read(vim.fs.joinpath(dir, 'codestyle.json')) or '{}',
      range = read(vim.fs.joinpath(dir, 'range')),
    })
  end
  return cases
end

return M
