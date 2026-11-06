-- The Spacing pass of the Engine. The Gap between two adjacent children is
-- owned by their parent, the lowest Block that holds both.

local M = {}

---@param block codestyle.Block
---@param lines string[]
---@param rules codestyle.Rules
---@param values codestyle.Values
---@param edits codestyle.Edit[]
local function visit(block, lines, rules, values, edits)
  for index = 2, #block.children do
    local left, right = block.children[index - 1], block.children[index]
    local row, start_col = left.range[3], left.range[4]
    local spacing = rules.spacing and rules.spacing(block, left, right, values)
    -- A Gap with a line break keeps its text.
    if spacing and row == right.range[1] then
      local end_col = right.range[2]
      local gap = lines[row + 1]:sub(start_col + 1, end_col)
      local count = math.min(math.max(#gap, spacing.min_spaces), spacing.max_spaces)
      local text = string.rep(' ', count)
      if text ~= gap then
        table.insert(edits, { start_row = row, start_col = start_col, end_row = row, end_col = end_col, text = text })
      end
    end
  end
  for _, child in ipairs(block.children) do
    visit(child, lines, rules, values, edits)
  end
end

--- The edits that give each Gap on one line the spaces its Spacing asks for.
---@param root codestyle.Block
---@param lines string[]
---@param rules codestyle.Rules
---@param values codestyle.Values
---@return codestyle.Edit[]
function M.edits(root, lines, rules, values)
  local edits = {}
  visit(root, lines, rules, values, edits)
  return edits
end

return M
