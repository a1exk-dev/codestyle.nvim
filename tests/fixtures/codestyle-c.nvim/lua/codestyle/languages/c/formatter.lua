-- The fake `c` formatter: its own `format(ctx)` instead of Blocks and rules.
-- It starts each top-level statement at column 0 and sets the spaces around
-- `=`. It keeps to the lines of `ctx.range`, as a plugin should.

---@param ctx codestyle.FormatContext
---@param row integer
---@return boolean
local function in_range(ctx, row)
  return not ctx.range or (row >= ctx.range.start_row and row <= ctx.range.end_row)
end

---@param row integer
---@param start_col integer
---@param end_col integer
---@param text string
---@return codestyle.Edit
local function edit(row, start_col, end_col, text)
  return { start_row = row, start_col = start_col, end_row = row, end_col = end_col, text = text }
end

---@param node TSNode
---@param ctx codestyle.FormatContext
---@param edits codestyle.Edit[]
local function space_assignments(node, ctx, edits)
  local parent = node:type()
  if parent == 'init_declarator' or parent == 'assignment_expression' then
    local spaces = ctx.values.spaces.around_assignment and ' ' or ''
    for child in node:iter_children() do
      if child:type() == '=' then
        local left, right = child:prev_sibling(), child:next_sibling()
        if left and right then
          local _, _, row, left_end = left:range()
          local _, operator_start, _, operator_end = child:range()
          local _, right_start = right:range()
          if in_range(ctx, row) then
            table.insert(edits, edit(row, left_end, operator_start, spaces))
            table.insert(edits, edit(row, operator_end, right_start, spaces))
          end
        end
      end
    end
  end
  for child in node:iter_children() do
    space_assignments(child, ctx, edits)
  end
end

---@type codestyle.Formatter
return {
  format = function(ctx)
    local edits = {}
    for statement in ctx.root:iter_children() do
      local row, col = statement:range()
      if col > 0 and in_range(ctx, row) then
        table.insert(edits, edit(row, 0, col, ''))
      end
    end
    space_assignments(ctx.root, ctx, edits)
    return edits
  end,
}
