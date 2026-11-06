-- The importer of a Scheme XML (ADR-0010): it resolves the field addresses
-- that each installed language's `scheme` module names, converts the values
-- by Option type, imports `<arrangement>` (ADR-0011) and the Core's own
-- `general` fields (ADR-0018), and reports what it could not import. It does
-- no I/O and changes nothing: the caller replaces the Draft with its patch.

local arrangement = require('codestyle.arrangement')
local code_style = require('codestyle.code_style')
local general = require('codestyle.general')
local general_scheme = require('codestyle.scheme_xml.general')
local regex_conversion = require('codestyle.regex_conversion')
local scheme_arrangement = require('codestyle.scheme_xml.arrangement')
local schema = require('codestyle.schema')

--- A value that the import set.
---@class codestyle.ImportedValue
---@field key string the dotted Option key, or `arrangement`
---@field value any

--- A field whose value is not valid for its Option: the default is used.
---@class codestyle.InvalidField
---@field key string the dotted Option key
---@field field string the field address, or the addresses of a join
---@field value any the field's text, or the fields of a join
---@field message string

--- What the import did for one language.
---@class codestyle.LanguageImport
---@field id string `general` or an installed language
---@field imported codestyle.ImportedValue[] sorted by key
---@field left_out string[] the addresses of the fields of Options that v1 leaves out, sorted
---@field unknown string[] the addresses of the fields that no entry names, sorted
---@field invalid codestyle.InvalidField[] sorted by key
---@field not_converted codestyle.NotConverted[] Java regexes and Arrangement parts
---@field arrangement? 'imported'|'default' nil when the language has no Arrangement or no `scheme`
---@field no_scheme? true the Language Plugin has no `scheme` module; the language is reset to its defaults

--- What an import gives before the Draft takes it.
---@class codestyle.SchemeImport
---@field patch codestyle.Patch the values of `general` and of every installed language, for `draft.replace`
---@field languages codestyle.LanguageImport[] `general` first, then the installed languages by id
---@field not_installed string[] the `language=` names and custom elements that no installed plugin reads, sorted

---@class codestyle.SchemeImporter
---@field import fun(root: codestyle.XmlElement): codestyle.SchemeImport?, codestyle.XmlError? nil and why when the root is no Scheme XML

local M = {}

--- The `<option>` child of an element with this name.
---@param element? codestyle.XmlElement
---@param name string
---@return codestyle.XmlElement?
local function option_named(element, name)
  for _, each in ipairs(element and element.children or {}) do
    if each.name == 'option' and each.attrs.name == name then
      return each
    end
  end
end

---@param element? codestyle.XmlElement
---@param name string
---@return codestyle.XmlElement?
local function child(element, name)
  for _, each in ipairs(element and element.children or {}) do
    if each.name == name then
      return each
    end
  end
end

--- The `<option>` children of an element.
---@param element? codestyle.XmlElement
---@return codestyle.XmlElement[]
local function options_of(element)
  return vim.tbl_filter(function(each)
    return each.name == 'option' and each.attrs.name ~= nil
  end, element and element.children or {})
end

---@param text string
---@return string[]
local function split(text)
  if vim.trim(text) == '' then
    return {}
  end
  return vim.tbl_map(vim.trim, vim.split(text, ',', { plain = true }))
end

--- A field's text as a value of the Option's type, before the Schema checks it.
---@param option codestyle.OptionSpec
---@param entry codestyle.SchemeEntry
---@param text string
---@return any
---@return string? problem
local function convert(option, entry, text)
  local kind = option.type
  if kind == 'boolean' then
    if text == 'true' or text == 'false' then
      return text == 'true'
    end
    return nil, ('expected true or false, got %s'):format(text)
  elseif kind == 'integer' then
    local number = text:match('^%s*(%-?%d+)%s*$')
    if not number then
      return nil, ('expected an integer, got %s'):format(text)
    end
    return tonumber(number)
  elseif kind == 'choice' then
    if not entry.values then
      return text
    end
    local id = entry.values[text]
    if not id then
      return nil, ('no choice for the PhpStorm value %s'):format(text)
    end
    return id
  elseif kind == 'list' or kind == 'order' then
    local items = split(text)
    if option.item ~= 'integer' then
      return items
    end
    local numbers = {} ---@type integer[]
    for index, item in ipairs(items) do
      numbers[index] = item:match('^%-?%d+$') and tonumber(item)
      if not numbers[index] then
        return nil, ('item %d: expected an integer, got %s'):format(index, item)
      end
    end
    return numbers
  end
  return text
end

---@param deps { registry: codestyle.Registry }
---@return codestyle.SchemeImporter
function M.new(deps)
  local registry = deps.registry

  ---@param root codestyle.XmlElement
  ---@return codestyle.SchemeImport?
  ---@return codestyle.XmlError?
  local function import(root)
    local code_scheme = root ---@type codestyle.XmlElement?
    if root.name == 'component' then
      code_scheme = child(root, 'code_scheme')
      if not code_scheme then
        return nil, { line = root.line, message = '<component> has no <code_scheme>' }
      end
    elseif root.name ~= 'code_scheme' then
      return nil, { line = root.line, message = ('the root element is <%s>, not <code_scheme>'):format(root.name) }
    end
    ---@cast code_scheme codestyle.XmlElement

    local blocks = {} ---@type table<string, codestyle.XmlElement>
    local elements = {} ---@type table<string, codestyle.XmlElement>
    for _, each in ipairs(code_scheme.children) do
      if each.name == 'codeStyleSettings' and each.attrs.language then
        blocks[each.attrs.language] = blocks[each.attrs.language] or each
      elseif each.name ~= 'option' then
        elements[each.name] = elements[each.name] or each
      end
    end
    local consumed = {} ---@type table<codestyle.XmlElement, true>

    --- The `<option>` that a field address names.
    ---@param address string
    ---@param scheme codestyle.Scheme
    ---@return codestyle.XmlElement?
    local function resolve(address, scheme)
      local parts = vim.split(address, ':', { plain = true })
      local form, name = parts[1], parts[#parts]
      if #parts == 2 and form == 'root' then
        return option_named(code_scheme, name)
      elseif #parts == 2 and form == 'other_indent' then
        return option_named(child(option_named(code_scheme, 'OTHER_INDENT_OPTIONS'), 'value'), name)
      elseif #parts == 2 and form == 'common' then
        return option_named(blocks[scheme.language], name)
      elseif #parts == 2 and form == 'indent' then
        return option_named(child(blocks[scheme.language], 'indentOptions'), name)
      elseif #parts == 2 and form == 'custom' then
        return scheme.element and option_named(elements[scheme.element], name)
      elseif #parts == 3 and form == 'tag' then
        return option_named(elements[parts[2]], name)
      elseif #parts == 4 and form == 'lang' and parts[3] == 'common' then
        return option_named(blocks[parts[2]], name)
      elseif #parts == 4 and form == 'lang' and parts[3] == 'indent' then
        return option_named(child(blocks[parts[2]], 'indentOptions'), name)
      end
      error(('the scheme of "%s" names the unknown field address "%s"'):format(scheme.language, address), 0)
    end

    --- A field's value: its `value` attribute, or the `<option>` itself when it has none.
    ---@param address string
    ---@param scheme codestyle.Scheme
    ---@return (string|codestyle.XmlElement)?
    local function field(address, scheme)
      local option = resolve(address, scheme)
      if not option then
        return nil
      end
      consumed[option] = true
      return option.attrs.value or option
    end

    ---@param id string
    ---@param spec { options: codestyle.OptionSpec[], arrangement?: codestyle.ArrangementSpec }
    ---@param scheme codestyle.Scheme
    ---@param values table<string, any> the patch of the language
    ---@return codestyle.LanguageImport
    local function import_language(id, spec, scheme, values)
      ---@type codestyle.LanguageImport
      local report = { id = id, imported = {}, left_out = {}, unknown = {}, invalid = {}, not_converted = {} }
      local options = {} ---@type table<string, codestyle.OptionSpec>
      for _, option in ipairs(spec.options) do
        options[option.key] = option
      end
      for _, entry in ipairs(scheme.entries) do
        local option = options[entry.key]
        if not option then
          error(('the scheme of "%s" names the unknown Option "%s"'):format(id, entry.key), 0)
        end
        local value, problem, raw, address
        if entry.from then
          address = table.concat(entry.fields, ', ')
          raw = {}
          for _, each in ipairs(entry.fields) do
            raw[each] = field(each, scheme)
          end
          if next(raw) ~= nil then
            value, problem = entry.from(raw)
          end
        else
          address = entry.field
          raw = field(entry.field, scheme)
          if type(raw) == 'table' then
            problem = 'expected a value attribute'
          elseif raw ~= nil and raw ~= '-1' then
            ---@cast raw string
            value, problem = convert(option, entry, raw)
          end
        end
        if value ~= nil and entry.java_regex_if and field(entry.java_regex_if, scheme) == 'true' then
          local converted, reason = regex_conversion.from_java(value)
          if not converted then
            table.insert(report.not_converted, {
              part = address,
              reason = ('cannot convert the Java regex "%s": %s'):format(value, reason),
            })
          end
          value = converted
        end
        if value ~= nil and not problem then
          value, problem = schema.check(option, value)
        end
        if problem then
          table.insert(report.invalid, { key = entry.key, field = address, value = raw, message = problem })
        elseif value ~= nil then
          values[entry.key] = value
          table.insert(report.imported, { key = entry.key, value = value })
        end
      end

      local block = blocks[scheme.language]
      if spec.arrangement then
        local element = child(block, 'arrangement')
        report.arrangement = 'default'
        if element then
          local raw, skipped = scheme_arrangement.convert(spec.arrangement, element)
          vim.list_extend(report.not_converted, skipped)
          local _, problem = arrangement.validate(spec.arrangement, raw)
          if problem then
            table.insert(report.not_converted, { part = problem.key, reason = problem.message })
          else
            values.arrangement = raw
            report.arrangement = 'imported'
            table.insert(report.imported, { key = 'arrangement', value = raw })
          end
        end
      end

      return report
    end

    --- Sorts the fields of the language's own blocks that no language read
    --- into left out and unknown. It runs after every language has read its
    --- fields, since a language may read another's (`tag:`, `lang:`).
    ---@param report codestyle.LanguageImport
    ---@param scheme codestyle.Scheme
    local function sort_unread(report, scheme)
      local left_out = {} ---@type table<string, true>
      for _, address in ipairs(scheme.left_out or {}) do
        left_out[address] = true
      end
      ---@param form string
      ---@param fields codestyle.XmlElement[] `<option>` elements
      local function sort_out(form, fields)
        for _, option in ipairs(fields) do
          if not consumed[option] then
            local address = form .. option.attrs.name
            table.insert(left_out[address] and report.left_out or report.unknown, address)
          end
        end
      end
      if report.id == general.id then
        local other_indent = option_named(code_scheme, 'OTHER_INDENT_OPTIONS')
        sort_out(
          'root:',
          vim.tbl_filter(function(option)
            return option ~= other_indent
          end, options_of(code_scheme))
        )
        sort_out('other_indent:', options_of(child(other_indent, 'value')))
      else
        local block = blocks[scheme.language]
        sort_out('common:', options_of(block))
        sort_out('indent:', options_of(child(block, 'indentOptions')))
        if scheme.element then
          sort_out('custom:', options_of(elements[scheme.element]))
        end
      end
      table.sort(report.imported, function(a, b)
        return a.key < b.key
      end)
      table.sort(report.invalid, function(a, b)
        return a.key < b.key
      end)
      table.sort(report.left_out)
      table.sort(report.unknown)
    end

    local patch = { [general.id] = {} } ---@type codestyle.Patch
    local reports = { import_language(general.id, general, general_scheme, patch[general.id]) }
    local schemes = { general_scheme } ---@type codestyle.Scheme[]
    local claimed = {} ---@type table<string, true>
    for _, id in ipairs(code_style.used_languages(registry)) do
      local spec = registry.get(id) --[[@as codestyle.Spec]]
      patch[id] = {}
      if spec.scheme then
        local scheme = registry.load(id, 'scheme') --[[@as codestyle.Scheme]]
        claimed[scheme.language] = true
        if scheme.element then
          claimed[scheme.element] = true
        end
        table.insert(reports, import_language(id, spec, scheme, patch[id]))
        schemes[#reports] = scheme
      else
        table.insert(
          reports,
          { id = id, imported = {}, left_out = {}, unknown = {}, invalid = {}, not_converted = {}, no_scheme = true }
        )
      end
    end

    for index, report in ipairs(reports) do
      if schemes[index] then
        sort_unread(report, schemes[index])
      end
    end

    local not_installed = {} ---@type string[]
    for name in pairs(blocks) do
      if not claimed[name] then
        table.insert(not_installed, name)
      end
    end
    for name in pairs(elements) do
      if not claimed[name] then
        table.insert(not_installed, name)
      end
    end
    table.sort(not_installed)
    return { patch = patch, languages = reports, not_installed = not_installed }
  end

  return { import = import }
end

return M
