-- The fake `lua` formatter: one Block per parser node (strings and comments
-- are leaves), Spacing rules written with `SpacingBuilder`, Indents of nested
-- Blocks and continuation lines, a Wrap of call arguments and Alignments, a
-- `before` step that removes semicolons and an `after` step that turns single
-- quotes into double quotes. The steps ignore `ctx.range` on purpose, so the
-- Core's dropping of edits outside it shows. Other fixtures reuse this
-- formatter with fewer Options, so it reads every value with a default.
-- `build` keeps a copy of `ctx.values` in `_G.codestyle_test_values` for tests,
-- and returns nil for the embedded fragment kind `expression`.

local alignment = require('codestyle.alignment')
local block = require('codestyle.block')
local indent = require('codestyle.indent')
local wrap = require('codestyle.wrap')
local spacing_builder = require('codestyle.spacing_builder')

--- The value at a dotted key, or `default` when the language has no such Option.
---@param key string
---@param default any
---@return fun(values: codestyle.Values): any
local function option(key, default)
  return function(values)
    local value = vim.tbl_get(values, unpack(vim.split(key, '.', { plain = true })))
    if value == nil then
      return default
    end
    return value
  end
end

--- Statements, for the blank lines between them.
local statements = {
  'variable_declaration',
  'assignment_statement',
  'function_call',
  'function_declaration',
  'if_statement',
  'return_statement',
}

local spacing = spacing_builder
  .new({ keep_blank_lines = option('blank_lines.keep_in_code', nil) })
  .between_inside(statements, statements, { 'chunk', 'block' })
  .spaces(1)
  .around_inside('=', { 'assignment_statement', 'field' })
  .space_if(option('spaces.around_assignment', false))
  .after(',')
  .space_if(option('spaces.after_comma', true))
  .before(',')
  .none()

--- Nodes whose body is a `block` between keywords.
local bodies = {
  function_declaration = true,
  function_definition = true,
  if_statement = true,
  elseif_statement = true,
  else_statement = true,
  while_statement = true,
  for_statement = true,
  repeat_statement = true,
  do_statement = true,
}

--- Children that end a body or continue a statement on its own level.
local closers = { ['end'] = true, elseif_statement = true, else_statement = true, ['until'] = true }

--- The Indent of a child relative to its parent.
---@param parent TSNode
---@param child TSNode
---@param index integer
---@return codestyle.Indent
local function child_indent(parent, child, index)
  local type, child_type = parent:type(), child:type()
  if type == 'chunk' or type == 'block' or index == 1 or closers[child_type] then
    return indent.none()
  elseif type == 'table_constructor' then
    return child_type == '}' and indent.none() or indent.normal()
  elseif type == 'arguments' or type == 'parameters' then
    return child_type == ')' and indent.none() or indent.continuation()
  elseif bodies[type] and (child_type == 'block' or child_type == 'comment') then
    return indent.normal()
  end
  return indent.continuation()
end

---@param node TSNode
---@param values codestyle.Values
---@return codestyle.Block
local function build_node(node, values)
  local type = node:type()
  local children = {}
  if type ~= 'string' and type ~= 'comment' then
    local index = 0
    for child in node:iter_children() do
      index = index + 1
      local child_block = build_node(child, values)
      child_block.indent = child_indent(node, child, index)
      table.insert(children, child_block)
    end
  end

  local wrap_type = ({ if_long = 'normal', chop_down = 'chop_down' })[option('wrap.call_arguments', 'off')(values)]
  local args_wrap = type == 'arguments' and wrap_type and wrap.new(wrap_type)
  local args_alignment = type == 'arguments' and option('align.call_arguments', false)(values) and alignment.new()
  local fields_alignment = type == 'table_constructor'
    and option('align.table_fields', false)(values)
    and alignment.new({ backward_shift = true })
  for _, child in ipairs(children) do
    if child.type ~= '(' and child.type ~= ')' and child.type ~= ',' then
      child.wrap = args_wrap or nil
      child.alignment = args_alignment or nil
    end
    if fields_alignment and child.type == 'field' and #child.children == 3 then
      -- The `=` of `name = value`.
      child.children[2].alignment = fields_alignment
    end
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
    if ctx.fragment == 'expression' then
      -- A kind of embedded code that this plugin cannot build (ADR-0008).
      return nil
    end
    return build_node(ctx.root, ctx.values)
  end,
  indent_options = function(values)
    return {
      size = option('indent.size', 4)(values),
      continuation = option('indent.continuation', 8)(values),
    }
  end,
  right_margin = option('wrap.hard_wrap_at', 120),
  rules = spacing.rules(),
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
