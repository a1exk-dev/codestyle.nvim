-- The fake `lua` plugin's `scheme` module (ADR-0007, ADR-0010): the PhpStorm
-- fields that its Options read, as field addresses that the Core resolves.

local MEMBERS = { 'fields', 'methods', 'metamethods' }

---@type codestyle.Scheme
return {
  language = 'Lua',
  element = 'LuaCodeStyleSettings',
  entries = {
    { key = 'spaces.around_assignment', field = 'common:SPACE_AROUND_ASSIGNMENT_OPERATORS' },
    { key = 'indent.size', field = 'indent:INDENT_SIZE' },
    { key = 'indent.continuation', field = 'other_indent:CONTINUATION_INDENT_SIZE' },
    {
      key = 'wrap.call_arguments',
      field = 'common:CALL_PARAMETERS_WRAP',
      values = { ['0'] = 'off', ['1'] = 'if_long', ['2'] = 'chop_down' },
    },
    { key = 'wrap.hard_wrap_at', field = 'common:RIGHT_MARGIN' },
    { key = 'wrap.visual_guides', field = 'common:SOFT_MARGINS' },
    { key = 'comments.todo', field = 'custom:TODO_MARKER' },
    { key = 'names.globals', field = 'custom:KNOWN_GLOBALS' },
    { key = 'conversion.double_quotes', field = 'tag:CCodeStyleSettings:USE_DOUBLE_QUOTES' },
    -- A join: three integer weights, as PhpStorm's PHPDoc tag order, become one `order`.
    {
      key = 'members.order',
      fields = { 'custom:FIELDS_WEIGHT', 'custom:METHODS_WEIGHT', 'custom:METAMETHODS_WEIGHT' },
      from = function(fields)
        ---@type table<string, any>
        local weights = {
          fields = fields['custom:FIELDS_WEIGHT'],
          methods = fields['custom:METHODS_WEIGHT'],
          metamethods = fields['custom:METAMETHODS_WEIGHT'],
        }
        if next(weights) == nil then
          return nil
        end
        local order = vim.deepcopy(MEMBERS)
        for index, member in ipairs(order) do
          weights[member] = tonumber(weights[member]) or index
        end
        table.sort(order, function(a, b)
          return weights[a] < weights[b]
        end)
        return order
      end,
    },
  },
  left_out = { 'custom:SPACE_BEFORE_SEMICOLON' },
}
