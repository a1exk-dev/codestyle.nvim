-- The fake `markdown` formatter: its own `format(ctx)` starts every line of
-- `ctx.range` at column 0, so a test sees which lines keep their column.

---@type codestyle.Formatter
return {
  format = function(ctx)
    local edits = {}
    for index, line in ipairs(vim.split(ctx.source, '\n', { plain = true })) do
      local row, indent = index - 1, #line:match('^ *')
      if indent > 0 and (not ctx.range or (row >= ctx.range.start_row and row <= ctx.range.end_row)) then
        table.insert(edits, { start_row = row, start_col = 0, end_row = row, end_col = indent, text = '' })
      end
    end
    return edits
  end,
}
