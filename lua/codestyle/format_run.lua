-- The Format Run (ADR-0002): the one run that formats real buffers, the
-- Preview and `codestyle.testing`. Today it runs the Engine's Spacing pass.

local engine = require('codestyle.engine')

---@class codestyle.FormatRequest
---@field lines string[]
---@field language string the language id
---@field parser string
---@field code_style codestyle.CodeStyle
---@field range? codestyle.Range the whole lines to format, nil for the whole text

--- Whole lines, rows 0-based and inclusive.
---@class codestyle.Range
---@field start_row integer
---@field end_row integer

---@class codestyle.FormatResult
---@field lines string[] the formatted lines
---@field edits codestyle.Edit[] the minimal edits, in text order

---@class codestyle.FormatRun
---@field run fun(request: codestyle.FormatRequest): codestyle.FormatResult

local M = {}

--- The lines with the edits applied.
---@param lines string[]
---@param edits codestyle.Edit[] in text order
---@return string[]
local function apply(lines, edits)
  local result = vim.list_slice(lines)
  for index = #edits, 1, -1 do
    local edit = edits[index]
    local text = result[edit.start_row + 1]:sub(1, edit.start_col)
      .. edit.text
      .. result[edit.end_row + 1]:sub(edit.end_col + 1)
    for _ = edit.start_row, edit.end_row do
      table.remove(result, edit.start_row + 1)
    end
    for offset, line in ipairs(vim.split(text, '\n', { plain = true })) do
      table.insert(result, edit.start_row + offset, line)
    end
  end
  return result
end

---@param deps { registry: codestyle.Registry }
---@return codestyle.FormatRun
function M.new(deps)
  ---@type codestyle.FormatRun
  return {
    run = function(request)
      local source = table.concat(request.lines, '\n')
      local tree = vim.treesitter.get_string_parser(source, request.parser):parse()[1]
      ---@type codestyle.FormatContext
      local ctx = {
        language = request.language,
        root = tree:root(),
        source = source,
        values = request.code_style.values(request.language),
      }
      local edits = engine.layout(ctx, deps.registry.load(request.language, 'formatter'))
      local range = request.range
      if range then
        edits = vim.tbl_filter(function(edit)
          return edit.start_row >= range.start_row and edit.end_row <= range.end_row
        end, edits)
      end
      table.sort(edits, function(a, b)
        return a.start_row < b.start_row or (a.start_row == b.start_row and a.start_col < b.start_col)
      end)
      return { lines = apply(request.lines, edits), edits = edits }
    end,
  }
end

return M
