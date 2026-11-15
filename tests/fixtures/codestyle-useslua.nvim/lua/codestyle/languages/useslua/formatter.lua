-- Builds with the used plugin's handler, `ctx.uses.lua.build`, and reads the
-- used plugin's values, `values.lua`.

local spacing = require('codestyle.spacing')

---@type codestyle.Formatter
return {
  build = function(ctx)
    return ctx.uses.lua.build(ctx)
  end,
  rules = {
    {
      nodes = { 'assignment_statement', '=' },
      spacing = function(parent, left, right, values)
        if parent.type == 'assignment_statement' and (left.type == '=' or right.type == '=') then
          return spacing.spaces(values.lua.spaces.around_assignment and 1 or 0)
        end
      end,
    },
  },
}
