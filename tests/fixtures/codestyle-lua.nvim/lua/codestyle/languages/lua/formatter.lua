-- The fake `lua` formatter: one Block per parser node, and one spacing rule.
-- `build` keeps a copy of `ctx.values` in `_G.codestyle_test_values` for tests.

local block = require('codestyle.block')
local spacing = require('codestyle.spacing')

---@param node TSNode
---@return codestyle.Block
local function build_node(node)
  local children = {}
  for child in node:iter_children() do
    table.insert(children, build_node(child))
  end
  return block.new({ node = node, children = children })
end

---@type codestyle.Formatter
return {
  build = function(ctx)
    -- Lets a test read the values that the Core passes to a plugin.
    _G.codestyle_test_values = vim.deepcopy(ctx.values)
    return build_node(ctx.root)
  end,
  rules = {
    spacing = function(parent, left, right, values)
      if parent.type == 'assignment_statement' and (left.type == '=' or right.type == '=') then
        return spacing.spaces(values.spaces.around_assignment and 1 or 0)
      end
    end,
  },
}
