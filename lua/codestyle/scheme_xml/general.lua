-- The Core's own `scheme` of `general` (ADR-0010, ADR-0018): the `root:`
-- fields of the six General Options. In regex mode the marker tags are Java
-- regexes, which the importer converts to Vim syntax.

---@param fields table<string, string|codestyle.XmlElement>
---@return string[]?
---@return string?
local function do_not_format(fields)
  local option = fields['root:DO_NOT_FORMAT']
  if type(option) ~= 'table' then
    return nil, 'expected a <list> of <fileSet> elements'
  end
  local patterns = {} ---@type string[]
  for _, list in ipairs(option.children) do
    for _, file_set in ipairs(list.name == 'list' and list.children or {}) do
      if file_set.attrs.type ~= 'globPattern' then
        return nil, ('cannot import the file set type "%s"; only globPattern'):format(tostring(file_set.attrs.type))
      end
      table.insert(patterns, file_set.attrs.pattern)
    end
  end
  return patterns
end

--- The field that turns regex mode on for the marker tags.
local REGEX = 'root:FORMATTER_TAGS_ACCEPT_REGEXP'

---@type codestyle.Scheme
return {
  language = '',
  entries = {
    { key = 'hard_wrap_at', field = 'root:RIGHT_MARGIN' },
    { key = 'do_not_format', fields = { 'root:DO_NOT_FORMAT' }, from = do_not_format },
    { key = 'markers.enabled', field = 'root:FORMATTER_TAGS_ENABLED' },
    { key = 'markers.regex', field = REGEX },
    { key = 'markers.off', field = 'root:FORMATTER_OFF_TAG', java_regex_if = REGEX },
    { key = 'markers.on', field = 'root:FORMATTER_ON_TAG', java_regex_if = REGEX },
  },
  -- The General controls that Reformat never applies (ADR-0018), and the
  -- indent of other file types, unless a plugin reads it.
  left_out = {
    'root:LINE_SEPARATOR',
    'root:WRAP_WHEN_TYPING_REACHES_RIGHT_MARGIN',
    'root:AUTODETECT_INDENTS',
    'root:SOFT_MARGINS',
    'other_indent:INDENT_SIZE',
    'other_indent:CONTINUATION_INDENT_SIZE',
    'other_indent:TAB_SIZE',
    'other_indent:USE_TAB_CHARACTER',
    'other_indent:SMART_TABS',
    'other_indent:LABEL_INDENT_SIZE',
    'other_indent:LABEL_INDENT_ABSOLUTE',
    'other_indent:USE_RELATIVE_INDENTS',
    'other_indent:KEEP_INDENTS_ON_EMPTY_LINES',
  },
}
