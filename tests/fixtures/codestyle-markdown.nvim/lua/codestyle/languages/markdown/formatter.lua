-- The fake `markdown` formatter: one Block per block node, words as leaves,
-- and an Embed Point for the body of each fenced code block (ADR-0008). The
-- info string names the language, then optional `parser=<key>` and
-- `fragment=<kind>`, so a test can pick the Embed Point's `parser_key` and
-- fragment kind. The items of a list are indented; every other Block starts
-- at its parent's indent. It has no Spacing rules.

local block = require('codestyle.block')
local embed = require('codestyle.embed')
local indent = require('codestyle.indent')
local words = require('codestyle.languages.markdown.words')

---@param node TSNode
---@param source string
---@return codestyle.Block?
local function fence_body(node, source)
  local info = node:parent() and node:parent():child(1)
  if not info or info:type() ~= 'info_string' then
    return nil
  end
  local parts = vim.split(vim.treesitter.get_node_text(info, source), '%s+', { trimempty = true })
  local opts = {}
  for index = 2, #parts do
    local key, value = parts[index]:match('^(%w+)=(.+)$')
    if key then
      opts[key] = value
    end
  end
  return embed.new({ node = node, language = parts[1], parser_key = opts.parser, fragment = opts.fragment or 'fence' })
end

---@param node TSNode
---@param source string
---@return codestyle.Block[]
local function build_node(node, source)
  local type = node:type()
  if type == 'code_fence_content' then
    local body = fence_body(node, source)
    if body then
      return { body }
    end
  end
  if type == 'inline' or node:child_count() == 0 or type == 'code_fence_content' then
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

---@param values codestyle.Values
---@param key string
---@param default any
---@return any
local function option(values, key, default)
  local value = vim.tbl_get(values, unpack(vim.split(key, '.', { plain = true })))
  if value == nil then
    return default
  end
  return value
end

---@type codestyle.Formatter
return {
  build = function(ctx)
    return build_node(ctx.root, ctx.source)[1] or block.new({ node = ctx.root })
  end,
  indent_options = function(values)
    return {
      size = option(values, 'indent.size', 4),
      continuation = option(values, 'indent.size', 4),
      use_tab = option(values, 'indent.use_tab', false),
      tab_size = option(values, 'indent.size', 4),
    }
  end,
  override_indent_options = function(values)
    return option(values, 'indent.same_in_whole_file', false)
  end,
}
