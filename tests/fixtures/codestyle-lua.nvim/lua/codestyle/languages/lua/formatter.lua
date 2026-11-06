-- The fake `lua` formatter: one Block per parser node, one spacing rule, a
-- `before` step that removes semicolons and an `after` step that turns
-- single quotes into double quotes. The steps ignore `ctx.range` on purpose,
-- so the Core's dropping of edits outside it shows. Other fixtures reuse this
-- formatter without the `conversion` Options, so the steps are off there.
-- `build` keeps a copy of `ctx.values` in `_G.codestyle_test_values` and counts
-- its calls in `_G.codestyle_test_builds`, for tests.

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

--- Every node of a type, in text order.
---@param node TSNode
---@param type string
---@param found? TSNode[]
---@return TSNode[]
local function find(node, type, found)
  found = found or {}
  if node:type() == type then
    table.insert(found, node)
  end
  for child in node:iter_children() do
    find(child, type, found)
  end
  return found
end

---@param node TSNode
---@param text string
---@return codestyle.Edit
local function replace(node, text)
  local start_row, start_col, end_row, end_col = node:range()
  return { start_row = start_row, start_col = start_col, end_row = end_row, end_col = end_col, text = text }
end

---@type codestyle.Formatter
return {
  build = function(ctx)
    -- Lets a test read the values that the Core passes to a plugin.
    _G.codestyle_test_values = vim.deepcopy(ctx.values)
    _G.codestyle_test_builds = (_G.codestyle_test_builds or 0) + 1
    return build_node(ctx.root)
  end,
  rules = {
    {
      nodes = { 'assignment_statement', '=' },
      spacing = function(parent, left, right, values)
        if parent.type == 'assignment_statement' and (left.type == '=' or right.type == '=') then
          return spacing.spaces(values.spaces.around_assignment and 1 or 0)
        end
      end,
    },
  },
  before = {
    function(ctx)
      if not vim.tbl_get(ctx.values, 'conversion', 'semicolons') then
        return {}
      end
      return vim.tbl_map(function(node)
        return replace(node, '')
      end, find(ctx.root, 'empty_statement'))
    end,
  },
  after = {
    function(ctx)
      if not vim.tbl_get(ctx.values, 'conversion', 'double_quotes') then
        return {}
      end
      local edits = {}
      for _, quote in ipairs(find(ctx.root, "'")) do
        table.insert(edits, replace(quote, '"'))
      end
      return edits
    end,
  },
}
