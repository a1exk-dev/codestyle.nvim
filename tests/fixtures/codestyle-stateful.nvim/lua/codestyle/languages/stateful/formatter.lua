-- Writes `-- run <n>` over the first line, where n counts the runs.

local runs = 0

---@type codestyle.Formatter
return {
  format = function(ctx)
    runs = runs + 1
    local first = vim.split(ctx.source, '\n', { plain = true })[1]
    return { { start_row = 0, start_col = 0, end_row = 0, end_col = #first, text = ('-- run %d'):format(runs) } }
  end,
}
