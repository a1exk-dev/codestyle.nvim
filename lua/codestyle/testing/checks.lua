-- The checks of `codestyle.testing` (ADR-0013): each Behaviour Record value
-- and file, each Arrangement case, each Preset and each hand-written case
-- becomes one check with a case id. Formatting checks go through the one
-- Format Run, twice (ADR-0016): formatter records with Arrangement off,
-- Arrangement cases with rearranging only (ADR-0011). Record fields go through
-- the plugin's `scheme` by the Core's Scheme XML importer, so Java marker
-- regexes go through Regex Conversion as on an import (ADR-0010, ADR-0018).

local address = require('codestyle.testing.address')
local code_style = require('codestyle.code_style')
local general = require('codestyle.general')
local general_scheme = require('codestyle.scheme_xml.general')
local migrations = require('codestyle.migrations')
local reader = require('codestyle.scheme_xml.reader')
local tree = require('codestyle.tree')

--- What one check found.
---@class codestyle.testing.Outcome
---@field status 'pass'|'fail'|'skip'
---@field message? string why it failed or was skipped
---@field skipped? string[] the values a Preset check left out

--- One check with its case id.
---@class codestyle.testing.Check
---@field id string `<record>/<base>/<value>/<file>`, `arrangement/<path>`, `preset/<name>` or `case/<name>`
---@field run fun(): codestyle.testing.Outcome
---@field flagged? { record: string, key: string, reason: string } the Flagged Option whose record the check belongs to

---@class codestyle.testing.Checks
---@field records fun(records: codestyle.testing.Record[], root: string): codestyle.testing.Check[]
---@field arrangement fun(cases: codestyle.testing.ArrangementCase[]): codestyle.testing.Check[]
---@field presets fun(presets: codestyle.testing.CorpusPreset[]): codestyle.testing.Check[]
---@field cases fun(cases: codestyle.testing.HandCase[]): codestyle.testing.Check[]

local M = {}

---@param message string
---@return codestyle.testing.Outcome
local function fail(message)
  return { status = 'fail', message = message }
end

---@param message string
---@return codestyle.testing.Outcome
local function skip(message)
  return { status = 'skip', message = message }
end

--- The lines of a text, and whether it ends with a newline.
---@param text string
---@return string[]
---@return boolean
local function to_lines(text)
  local final = text:sub(-1) == '\n'
  return vim.split(final and text:sub(1, -2) or text, '\n', { plain = true }), final
end

--- The changes from one text to another, as unified hunks without context.
---@param from string
---@param to string
---@return string
local function diff(from, to)
  local text_diff = vim.text and vim.text.diff or vim.diff ---@diagnostic disable-line: deprecated
  return text_diff(from, to, { ctxlen = 0 }) --[[@as string]]
end

--- The nested stored shape of a patch's dotted keys.
---@param patch codestyle.Patch
---@return table<string, table>
local function nest(patch)
  local languages = {}
  for id, values in pairs(patch) do
    languages[id] = {}
    for key, value in pairs(values) do
      tree.set(languages[id], tree.path(key), vim.deepcopy(value))
    end
  end
  return languages
end

---@param value any
---@return string
local function show(value)
  return vim.inspect(value, { newline = ' ', indent = '' })
end

---@param deps { registry: codestyle.Registry, format_run: codestyle.FormatRun, importer: codestyle.SchemeImporter, presets: codestyle.Presets, language: string, parser: string }
---@return codestyle.testing.Checks
function M.new(deps)
  local registry = deps.registry
  local spec = registry.get(deps.language) --[[@as codestyle.Spec]]
  local scheme = spec.scheme and registry.load(deps.language, 'scheme') --[[@as codestyle.Scheme?]]

  --- The `scheme` of `general` and of every used language, with the spec it maps.
  ---@type { id: string, scheme: codestyle.Scheme, options: codestyle.OptionSpec[] }[]
  local schemes = { { id = general.id, scheme = general_scheme, options = general.options } }
  for _, id in ipairs(code_style.used_languages(registry)) do
    local each = registry.get(id) --[[@as codestyle.Spec]]
    if each.scheme then
      table.insert(schemes, { id = id, scheme = registry.load(id, 'scheme'), options = each.options })
    end
  end

  --- The Options that read a field, and whether a scheme leaves it out.
  ---@param field string relative to the tested language's `scheme`
  ---@return { id: string, option: codestyle.OptionSpec }[] owners
  ---@return boolean left_out
  local function owners(field)
    local absolute = address.absolute(field, scheme --[[@as codestyle.Scheme]])
    local found, left_out = {}, false
    for _, each in ipairs(schemes) do
      local options = {} ---@type table<string, codestyle.OptionSpec>
      for _, option in ipairs(each.options) do
        options[option.key] = option
      end
      for _, entry in ipairs(each.scheme.entries) do
        for _, read in ipairs(entry.fields or { entry.field }) do
          if address.absolute(read, each.scheme) == absolute and options[entry.key] then
            table.insert(found, { id = each.id, option = options[entry.key] })
          end
        end
      end
      for _, out in ipairs(each.scheme.left_out or {}) do
        left_out = left_out or address.absolute(out, each.scheme) == absolute
      end
    end
    return found, left_out
  end

  --- Imports a Scheme XML tree: the stored languages, or nil and why it does not import whole.
  ---@param root codestyle.XmlElement
  ---@return table<string, table>?
  ---@return string?
  ---@return codestyle.SchemeImport?
  local function import(root)
    local ok, imported, problem = pcall(deps.importer.import, root)
    if not ok then
      return nil, tostring(imported)
    elseif not imported then
      return nil, problem and problem.message
    end
    local problems = {}
    for _, language in ipairs(imported.languages) do
      for _, invalid in ipairs(language.invalid) do
        table.insert(problems, ('%s: invalid value %s: %s'):format(invalid.field, show(invalid.value), invalid.message))
      end
      for _, part in ipairs(language.not_converted) do
        table.insert(problems, ('%s: %s'):format(part.part, part.reason))
      end
    end
    if #problems > 0 then
      return nil, 'the settings do not import: ' .. table.concat(problems, '; ')
    end
    return nest(imported.patch), nil, imported
  end

  --- Formats a text twice through the Format Run and compares the first output with the
  --- expected text and the second with the first.
  ---@param request { input: string, expected: string, languages: table, path: string, root: string, range?: codestyle.Range, arrangement: codestyle.ArrangementMode }
  ---@return codestyle.testing.Outcome
  local function format(request)
    local lines, final = to_lines(request.input)
    local style = code_style.new({ version = 1, languages = request.languages }, registry)
    local outputs = {}
    for run = 1, 2 do
      local result, failure = deps.format_run.run({
        lines = vim.deepcopy(lines),
        language = deps.language,
        parser = deps.parser,
        code_style = style,
        range = request.range,
        path = request.path,
        root = request.root,
        arrangement = request.arrangement,
      })
      if not result then
        return fail('the Language Plugin failed: ' .. (failure --[[@as codestyle.FormatFailure]]).message)
      end
      local text = table.concat(result.lines, result.fileformat == 'dos' and '\r\n' or '\n')
      outputs[run] = final and text .. (result.fileformat == 'dos' and '\r\n' or '\n') or text
    end
    if outputs[1] ~= request.expected then
      return fail('the output differs:\n' .. diff(request.expected, outputs[1]))
    end
    if outputs[2] ~= outputs[1] then
      return fail(
        'a second run gave another output, so the Language Plugin keeps state between runs:\n'
          .. diff(outputs[1], outputs[2])
      )
    end
    return { status = 'pass' }
  end

  --- The settings of a record value, or the outcome that ends its cases.
  ---@param base_settings table<string, string>
  ---@param field string
  ---@param result codestyle.testing.RecordResult
  ---@param xml boolean
  ---@return codestyle.testing.Setting[]?
  ---@return codestyle.testing.Outcome?
  local function settings_of(base_settings, field, result, xml)
    local settings = {} ---@type codestyle.testing.Setting[]
    local spellings = vim.tbl_keys(base_settings)
    table.sort(spellings)
    for _, spelling in ipairs(spellings) do
      local base_field, kind = address.from_corpus(spelling)
      if kind == 'editorconfig' then
        return nil, skip(('the base sets the .editorconfig field %s; the Core reads no .editorconfig'):format(spelling))
      elseif not base_field then
        return nil, fail(('cannot translate the base setting %s to a field address'):format(spelling))
      end
      local found, left_out = owners(base_field)
      if #found == 0 and left_out then
        return nil, skip(('the base sets the left-out field %s'):format(base_field))
      elseif #found == 0 then
        return nil, fail(('no Option of an installed Language Plugin reads the field %s'):format(base_field))
      end
      table.insert(settings, { address = base_field, value = base_settings[spelling], xml = kind == 'xml' })
    end
    table.insert(settings, { address = field, value = result.internal, xml = xml })
    return settings
  end

  ---@param record codestyle.testing.Record
  ---@param root string
  ---@return codestyle.testing.Check[]
  local function record_checks(record, root)
    ---@param outcome codestyle.testing.Outcome
    local function whole(outcome)
      return {
        {
          id = record.key,
          run = function()
            return outcome
          end,
        },
      }
    end
    if record.status == 'untestable-via-cli' then
      return whole(skip('untestable-via-cli'))
    end
    if not scheme then
      return whole(fail(('the Language Plugin "%s" has no scheme module'):format(deps.language)))
    end
    local field, kind = address.from_corpus(record.scheme_xml_location or {})
    if kind == 'editorconfig' then
      return whole(skip('an .editorconfig field; the Core reads no .editorconfig'))
    elseif not field then
      return whole(fail(('cannot translate scheme_xml_location %s'):format(show(record.scheme_xml_location))))
    end
    local found, left_out = owners(field)
    if #found == 0 and left_out then
      return whole(skip(('the field %s is left out'):format(field)))
    end
    local flagged ---@type { record: string, key: string, reason: string }?
    for _, owner in ipairs(found) do
      if owner.option.flagged and not flagged then
        flagged = { record = record.key, key = owner.option.key, reason = owner.option.flagged }
      end
    end

    local files = vim.tbl_keys(record.inputs or {})
    table.sort(files)
    local checks = {} ---@type codestyle.testing.Check[]
    for _, result in ipairs(record.results) do
      local settings, ended = settings_of(result.base_settings or {}, field, result, kind == 'xml')
      if #found == 0 then
        settings, ended = nil, fail(('no Option of an installed Language Plugin reads the field %s'):format(field))
      end
      for _, file in ipairs(files) do
        table.insert(checks, {
          id = table.concat({ record.key, result.base, result.value, file }, '/'),
          flagged = flagged,
          run = function()
            if ended then
              return ended
            end
            local xml, problem = address.to_xml(settings --[[@as codestyle.testing.Setting[] ]], scheme)
            if not xml then
              return fail(problem --[[@as string]])
            end
            local languages, not_imported = import(xml)
            if not languages then
              return fail(not_imported --[[@as string]])
            end
            local changed = (result.changed_files or {})[file]
            local expected = changed and changed.output or vim.tbl_get(record.base_outputs or {}, result.base, file)
            if not expected then
              return fail(('the record has no output of %s on the base "%s"'):format(file, result.base))
            end
            return format({
              input = record.inputs[file],
              expected = expected,
              languages = languages,
              path = vim.fs.joinpath(root, file),
              root = root,
              arrangement = 'off',
            })
          end,
        })
      end
    end
    return checks
  end

  --- The stored languages of an `arrangement.xml`: an `<arrangement>` of the tested language, a
  --- whole `<codeStyleSettings>` block, or `default` (none stored: the plugin's default).
  ---@param text string
  ---@return table<string, table>?
  ---@return string?
  local function arrangement_of(text)
    if text == 'default' then
      return {}
    end
    if not scheme then
      return nil, ('the Language Plugin "%s" has no scheme module'):format(deps.language)
    end
    local element, broken = reader.parse(text)
    if not element then
      ---@cast broken codestyle.XmlError
      return nil, ('arrangement.xml:%d: %s'):format(broken.line, broken.message)
    end
    if element.name == 'arrangement' then
      element = {
        name = 'codeStyleSettings',
        attrs = { language = scheme.language },
        children = { element },
        text = '',
        line = 0,
      }
    end
    return import({ name = 'code_scheme', attrs = {}, children = { element }, text = '', line = 0 })
  end

  --- The Option values of each language that a patch sets, resolved, by `<id>.<key>`.
  ---@param patch codestyle.Patch
  ---@param keys table<string, true> gets every `<id>.<key>` of the patch
  ---@return codestyle.CodeStyle
  local function resolved(patch, keys)
    for id, values in pairs(patch) do
      for key in pairs(values) do
        if key ~= 'arrangement' then
          keys[id .. '.' .. key] = true
        end
      end
    end
    return code_style.new({ version = 1, languages = nest(patch) }, registry)
  end

  ---@param preset codestyle.testing.CorpusPreset
  ---@return codestyle.testing.Outcome
  local function check_preset(preset)
    local own = vim.iter(spec.presets or {}):find(function(each)
      return each.name == preset.name
    end)
    if not own then
      return fail(('the spec of "%s" has no Preset named "%s"'):format(deps.language, preset.name))
    end
    local element, broken = reader.parse(preset.scheme_xml_diff)
    if not element then
      ---@cast broken codestyle.XmlError
      return fail(('scheme_xml_diff:%d: %s'):format(broken.line, broken.message))
    end
    local ok, imported, problem = pcall(deps.importer.import, element)
    if not ok or not imported then
      return fail(ok and (problem and problem.message or '') or tostring(imported))
    end
    local skipped, problems = {}, {}
    for _, language in ipairs(imported.languages) do
      for _, field in ipairs(language.left_out) do
        table.insert(skipped, ('%s %s: left out'):format(language.id, field))
      end
      for _, field in ipairs(language.unknown) do
        table.insert(problems, ('%s %s: no Option reads this field'):format(language.id, field))
      end
      for _, invalid in ipairs(language.invalid) do
        table.insert(problems, ('%s %s: %s'):format(language.id, invalid.field, invalid.message))
      end
      for _, part in ipairs(language.not_converted) do
        table.insert(problems, ('%s %s: %s'):format(language.id, part.part, part.reason))
      end
    end
    for _, name in ipairs(imported.not_installed) do
      table.insert(skipped, name .. ': no installed Language Plugin')
    end
    local patch, preset_skipped = deps.presets.to_patch(own)
    for _, value in ipairs(preset_skipped) do
      table.insert(skipped, ('%s: %s'):format(value.key, value.reason))
    end

    local keys = {} ---@type table<string, true>
    local from_scheme = resolved(imported.patch, keys)
    local from_preset = resolved(patch, keys)
    local sorted = vim.tbl_keys(keys)
    table.sort(sorted)
    for _, key in ipairs(sorted) do
      local id, option = key:match('^([^.]+)%.(.+)$')
      local path = tree.path(option)
      local want, got = tree.get(from_preset.values(id), path), tree.get(from_scheme.values(id), path)
      if not vim.deep_equal(want, got) then
        table.insert(problems, ('%s: the Preset sets %s, the scheme diff %s'):format(key, show(want), show(got)))
      end
    end
    table.sort(skipped)
    local outcome = #problems > 0 and fail(table.concat(problems, '\n')) or { status = 'pass' }
    outcome.skipped = skipped
    return outcome
  end

  ---@param case codestyle.testing.HandCase
  ---@return codestyle.testing.Outcome
  local function check_case(case)
    if not case.output then
      return fail('the case has no output file')
    end
    local ok, stored = pcall(vim.json.decode, case.codestyle)
    if not ok or type(stored) ~= 'table' or vim.islist(stored) and next(stored) ~= nil then
      return fail('codestyle.json is not a JSON object: ' .. tostring(stored))
    end
    local range ---@type codestyle.Range?
    if case.range then
      local first, last = case.range:match('^%s*(%d+)[%s,]+(%d+)%s*$')
      if not first then
        return fail(('the range "%s" is not two line numbers'):format(vim.trim(case.range)))
      end
      range = { start_row = tonumber(first) - 1, end_row = tonumber(last) - 1 }
    end
    return format({
      input = case.input,
      expected = case.output,
      languages = { [deps.language] = migrations.apply(spec.migrations or {}, stored) },
      path = case.input_path,
      root = case.dir,
      range = range,
      arrangement = 'auto',
    })
  end

  ---@type codestyle.testing.Checks
  return {
    records = function(records, root)
      local checks = {}
      for _, record in ipairs(records) do
        vim.list_extend(checks, record_checks(record, root))
      end
      return checks
    end,
    arrangement = function(cases)
      return vim.tbl_map(function(case)
        ---@cast case codestyle.testing.ArrangementCase
        return {
          id = 'arrangement/' .. case.name,
          run = function()
            local languages, problem = arrangement_of(case.xml)
            if not languages then
              return fail(problem --[[@as string]])
            end
            return format({
              input = case.input,
              expected = case.output,
              languages = languages,
              path = case.input_path,
              root = vim.fs.dirname(case.input_path),
              arrangement = 'only',
            })
          end,
        }
      end, cases)
    end,
    presets = function(presets)
      return vim.tbl_map(function(preset)
        return {
          id = 'preset/' .. preset.name,
          run = function()
            return check_preset(preset)
          end,
        }
      end, presets)
    end,
    cases = function(cases)
      return vim.tbl_map(function(case)
        return {
          id = 'case/' .. case.name,
          run = function()
            return check_case(case)
          end,
        }
      end, cases)
    end,
  }
end

return M
