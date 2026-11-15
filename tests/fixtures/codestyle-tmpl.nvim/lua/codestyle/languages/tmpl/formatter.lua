-- The fake template host's formatter: one Block per block node, with a
-- template-layer Embed Point (a hole) for each inline and each fenced body.
-- The items of a list are indented, and so is the markup that the merge puts
-- in a fenced block. Its Spacing: two spaces after a list marker, and two
-- between the Blocks of a fenced body.

local block = require('codestyle.block')
local embed = require('codestyle.embed')
local indent = require('codestyle.indent')
local spacing = require('codestyle.spacing')
local words = require('codestyle.languages.markdown.words')

local delimiters = { fenced_code_block_delimiter = true, info_string = true }

---@param node TSNode
---@param source string
---@return codestyle.Block[]
local function build_node(node, source)
  local type = node:type()
  if type == 'inline' or type == 'code_fence_content' then
    return { embed.new({ node = node, language = 'inl', template = true }) }
  end
  if node:child_count() == 0 then
    local start_row, start_col, end_row, end_col = node:range()
    return words.in_range(source, { start_row, start_col, end_row, end_col })
  end
  -- The child nodes' Blocks, and words for the node's own text between them.
  local start_row, start_col, end_row, end_col = node:range()
  local children, skip = {}, {}
  for child in node:iter_children() do
    vim.list_extend(children, build_node(child, source))
    local child_start_row, child_start_col, child_end_row, child_end_col = child:range()
    table.insert(skip, { child_start_row, child_start_col, child_end_row, child_end_col })
  end
  vim.list_extend(children, words.in_range(source, { start_row, start_col, end_row, end_col }, skip))
  table.sort(children, function(a, b)
    return a.range[1] < b.range[1] or (a.range[1] == b.range[1] and a.range[2] < b.range[2])
  end)
  for index, child_block in ipairs(children) do
    if type == 'list_item' and index > 1 then
      child_block.indent = indent.normal()
    end
  end
  if #children == 0 then
    return {}
  end
  return { block.new({ node = node, range = words.span(children), children = children }) }
end

---@type codestyle.Formatter
return {
  build = function(ctx)
    return build_node(ctx.root, ctx.source)[1]
  end,
  indent_options = function(values)
    local size = vim.tbl_get(values, 'indent', 'size') or 4
    return { size = size, continuation = size }
  end,
  rules = {
    {
      nodes = { 'list_item', 'list_marker_minus' },
      spacing = function(parent, left)
        if parent.type == 'list_item' and left.type == 'list_marker_minus' then
          return spacing.spaces(2)
        end
      end,
    },
    {
      nodes = { 'fenced_code_block' },
      spacing = function(parent, left, right)
        if parent.type == 'fenced_code_block' and not delimiters[left.type] and not delimiters[right.type] then
          return spacing.spaces(2)
        end
      end,
      child_indent = function(parent, child)
        if parent.type == 'fenced_code_block' and not delimiters[child.type] then
          return indent.normal()
        end
      end,
    },
  },
}
