-- The Core's own `general` language (ADR-0018): the six General Options that
-- change what Reformat outputs. It is plain data, like a Language Plugin's
-- spec, but it formats nothing itself.

---@class codestyle.GeneralSpec
---@field id 'general'
---@field name string
---@field options codestyle.OptionSpec[]
---@field tabs codestyle.Tab[] PhpStorm's two Tabs of the General page (ADR-0018)

--- The marker Options are dimmed while markers are off (ADR-0018).
---@type codestyle.Requirement
local MARKERS_ON = { key = 'markers.enabled', is = true }

---@type codestyle.GeneralSpec
return {
  id = 'general',
  name = 'General',
  options = {
    { key = 'hard_wrap_at', type = 'integer', min = 1, max = 1000, default = 120, label = 'Hard wrap at' },
    { key = 'do_not_format', type = 'list', item = 'string', default = {}, label = 'Do not format' },
    {
      key = 'markers.enabled',
      type = 'boolean',
      default = true,
      label = 'Turn formatter on/off with markers in code comments',
    },
    {
      key = 'markers.off',
      type = 'string',
      default = '@formatter:off',
      label = 'Formatter off',
      requires = MARKERS_ON,
    },
    { key = 'markers.on', type = 'string', default = '@formatter:on', label = 'Formatter on', requires = MARKERS_ON },
    {
      key = 'markers.regex',
      type = 'boolean',
      default = false,
      label = 'Enable regular expressions in formatter markers',
      requires = MARKERS_ON,
    },
  },
  tabs = {
    { name = 'General', rows = { 'hard_wrap_at' } },
    {
      name = 'Formatter',
      rows = {
        'do_not_format',
        {
          label = 'Formatter markers',
          option = 'markers.enabled',
          rows = { 'markers.off', 'markers.on', 'markers.regex' },
        },
      },
    },
  },
}
