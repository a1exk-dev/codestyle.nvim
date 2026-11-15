-- Field addresses for `codestyle.testing`: the Research Corpus spells the
-- fields of a Behaviour Record in its own way (`common:INDENT.INDENT_SIZE`,
-- `otherindent:…`, `raw:…`), and ADR-0010 spells them as the `scheme`
-- modules do (`indent:INDENT_SIZE`, `other_indent:…`, `root:…`). This module
-- translates one into the other, and builds the Scheme XML tree that a set of
-- fields stands for, so the Core's importer maps them through `scheme`.

local reader = require('codestyle.scheme_xml.reader')

local M = {}

--- A field of a record with the value to set.
---@class codestyle.testing.Setting
---@field address string the ADR-0010 address, relative to the tested language's `scheme`
---@field value string the scheme-XML spelling; for `xml`, the whole `<option>` element
---@field xml? boolean the value is an `<option>` element, as the corpus' `raw:` fields

--- The ADR-0010 address of a corpus spelling, such as `common:INDENT.INDENT_SIZE`
--- or the location `{ 'tag:CCodeStyleSettings', 'USE_DOUBLE_QUOTES' }`.
---@param spelling string|string[]
---@return string? address nil when it names no Scheme XML field
---@return 'xml'|'editorconfig'|'unknown'|nil kind `xml` for a field whose value is an element; else why there is no address
function M.from_corpus(spelling)
  if type(spelling) == 'table' then
    spelling = table.concat(spelling, ':')
  end
  local form, rest = spelling:match('^([%w_]+):(.+)$')
  if form == 'common' then
    local indent = rest:match('^INDENT%.(.+)$')
    return indent and 'indent:' .. indent or 'common:' .. rest
  elseif form == 'custom' or form == 'root' then
    return form .. ':' .. rest
  elseif form == 'raw' then
    return 'root:' .. rest, 'xml'
  elseif form == 'otherindent' then
    return 'other_indent:' .. rest
  elseif form == 'tag' and rest:match('^[^:]+:[^:]+$') then
    return 'tag:' .. rest
  elseif form == 'lang' then
    local language, field = rest:match('^([^:]+):(.+)$')
    if language then
      local indent = field:match('^INDENT%.(.+)$')
      return indent and ('lang:%s:indent:%s'):format(language, indent) or ('lang:%s:common:%s'):format(language, field)
    end
  elseif form == 'ecfile' then
    return nil, 'editorconfig'
  end
  return nil, 'unknown'
end

--- The address with the language's own forms (`common:`, `indent:`, `custom:`) spelled out, so
--- that the addresses of two `scheme` modules compare.
---@param address string
---@param scheme codestyle.Scheme
---@return string
function M.absolute(address, scheme)
  local form, name = address:match('^([%w_]+):([^:]+)$')
  if form == 'common' or form == 'indent' then
    return ('lang:%s:%s:%s'):format(scheme.language, form, name)
  elseif form == 'custom' and scheme.element then
    return ('tag:%s:%s'):format(scheme.element, name)
  end
  return address
end

---@param name string
---@param attrs? table<string, string>
---@return codestyle.XmlElement
local function element(name, attrs)
  return { name = name, attrs = attrs or {}, children = {}, text = '', line = 0 }
end

--- The `<code_scheme>` that sets these fields and nothing else.
---@param settings codestyle.testing.Setting[]
---@param scheme codestyle.Scheme the tested language's
---@return codestyle.XmlElement? root
---@return string? problem a `raw:` value that is no XML
function M.to_xml(settings, scheme)
  local root = element('code_scheme')
  local children = {} ---@type table<string, codestyle.XmlElement>

  --- The child element with this key, created once.
  ---@param parent codestyle.XmlElement
  ---@param key string
  ---@param make fun(): codestyle.XmlElement
  ---@return codestyle.XmlElement
  local function child(parent, key, make)
    if not children[key] then
      children[key] = make()
      table.insert(parent.children, children[key])
    end
    return children[key]
  end

  for _, setting in ipairs(settings) do
    local parts = vim.split(M.absolute(setting.address, scheme), ':', { plain = true })
    local form, name = parts[1], parts[#parts]
    local parent ---@type codestyle.XmlElement
    if form == 'root' then
      parent = root
    elseif form == 'other_indent' then
      local other = child(root, 'other_indent', function()
        return element('option', { name = 'OTHER_INDENT_OPTIONS' })
      end)
      parent = child(other, 'other_indent/value', function()
        return element('value')
      end)
    elseif form == 'tag' then
      parent = child(root, 'tag:' .. parts[2], function()
        return element(parts[2])
      end)
    else -- `lang:<Language>:common:` and `lang:<Language>:indent:`
      parent = child(root, 'lang:' .. parts[2], function()
        return element('codeStyleSettings', { language = parts[2] })
      end)
      if parts[3] == 'indent' then
        local block = parent
        parent = child(block, 'lang:' .. parts[2] .. ':indent', function()
          return element('indentOptions')
        end)
      end
    end
    if setting.xml then
      local option, problem = reader.parse(setting.value)
      if not option then
        return nil, ('the value of %s is no XML: %s'):format(setting.address, problem and problem.message)
      end
      table.insert(parent.children, option)
    else
      table.insert(parent.children, element('option', { name = name, value = setting.value }))
    end
  end
  return root
end

return M
