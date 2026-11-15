-- The `luanext` formatter: one Block per parser node and two rules. The first
-- needs `augmented_assignment`, which the bundled `lua` grammar lacks; if the
-- Core ran it, every `=` would get three spaces.

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
    return build_node(ctx.root)
  end,
  rules = {
    {
      nodes = { 'augmented_assignment', '=' },
      spacing = function(_, left, right)
        if left.type == '=' or right.type == '=' then
          return spacing.spaces(3)
        end
      end,
    },
    {
      nodes = { 'assignment_statement', '=' },
      spacing = function(parent, left, right, values)
        if parent.type == 'assignment_statement' and (left.type == '=' or right.type == '=') then
          return spacing.spaces(values.spaces.around_assignment and 1 or 0)
        end
      end,
    },
  },
}
