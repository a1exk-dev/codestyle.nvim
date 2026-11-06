-- The fake template layer's formatter: one Block per node of the combined
-- inline tree, and words as leaves. The Blocks after the first one of an
-- emphasis are indented, also host Blocks that the merge puts there. Its
-- Spacing: one space between the Blocks of an emphasis or of the root, except
-- next to a delimiter.

local block = require('codestyle.block')
local indent = require('codestyle.indent')
local spacing = require('codestyle.spacing')
local words = require('codestyle.languages.markdown.words')

---@param node TSNode
---@param source string
---@return codestyle.Block
local function build_node(node, source)
  local start_row, start_col, end_row, end_col = node:range()
  local range = { start_row, start_col, end_row, end_col }
  if node:named_child_count() == 0 and node:type() ~= 'inline' then
    return block.new({ node = node })
  end
  local children, skip = {}, {}
  for child in node:iter_children() do
    if child:named() then
      table.insert(children, build_node(child, source))
      local child_start_row, child_start_col, child_end_row, child_end_col = child:range()
      table.insert(skip, { child_start_row, child_start_col, child_end_row, child_end_col })
    end
  end
  vim.list_extend(children, words.in_range(source, range, skip))
  table.sort(children, function(a, b)
    return a.range[1] < b.range[1] or (a.range[1] == b.range[1] and a.range[2] < b.range[2])
  end)
  for index, child in ipairs(children) do
    if node:type() == 'emphasis' and index > 1 then
      child.indent = indent.normal()
    end
  end
  return block.new({ node = node, range = range, children = children })
end

local owners = { inline = true, emphasis = true }

---@type codestyle.Formatter
return {
  build = function(ctx)
    return build_node(ctx.root, ctx.source)
  end,
  indent_options = function(values)
    local size = vim.tbl_get(values, 'indent', 'size') or 4
    return { size = size, continuation = size }
  end,
  rules = {
    {
      nodes = { 'inline', 'emphasis', 'emphasis_delimiter' },
      spacing = function(parent, left, right)
        if owners[parent.type] and left.type ~= 'emphasis_delimiter' and right.type ~= 'emphasis_delimiter' then
          return spacing.spaces(1)
        end
      end,
      child_indent = function(parent, child)
        if parent.type == 'emphasis' and parent.children[1] ~= child then
          return indent.normal()
        end
      end,
    },
  },
}
