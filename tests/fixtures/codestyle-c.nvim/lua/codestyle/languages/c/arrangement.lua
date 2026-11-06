-- The fake `c` Arrangement module (ADR-0011): each top-level declaration is
-- an entry named by its first declarator, as a CSS declaration by its property.

local entry = require('codestyle.arrangement_entry')

local M = {}

--- The name of the first identifier under a node.
---@param node TSNode
---@param source string
---@return string?
local function first_identifier(node, source)
  if node:type() == 'identifier' then
    return vim.treesitter.get_node_text(node, source)
  end
  for child in node:iter_children() do
    local name = first_identifier(child, source)
    if name then
      return name
    end
  end
end

---@param ctx codestyle.ArrangementContext
---@return codestyle.ArrangementEntry[]
function M.entries(ctx)
  local entries = {}
  for child in ctx.root:iter_children() do
    local declarator = child:type() == 'declaration' and child:field('declarator')[1]
    if declarator then
      table.insert(
        entries,
        entry.new({ node = child, types = { 'declaration' }, name = first_identifier(declarator, ctx.source) })
      )
    end
  end
  return entries
end

return M
