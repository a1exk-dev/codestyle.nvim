-- The Spacing pass of the Engine. The Gap between two adjacent children is
-- owned by their parent, the lowest Block that holds both.

local M = {}

--- The Spacing of the first rule that gives one, or nil to keep the Gap.
---@param rules codestyle.Rule[]
---@return codestyle.Spacing?
local function spacing_of(rules, parent, left, right, values)
  for _, rule in ipairs(rules) do
    local spacing = rule.spacing and rule.spacing(parent, left, right, values)
    if spacing then
      return spacing
    end
  end
end

---@param block codestyle.Block
---@param lines string[]
---@param rules codestyle.Rule[]
---@param values codestyle.Values
---@param read_only codestyle.ReadOnly
---@param edits codestyle.Edit[]
local function visit(block, lines, rules, values, read_only, edits)
  for index = 2, #block.children do
    local left, right = block.children[index - 1], block.children[index]
    local row, start_col = left.range[3], left.range[4]
    local spacing = spacing_of(rules, block, left, right, values)
    -- A Gap with a line break keeps its text.
    if spacing and row == right.range[1] then
      local end_col = right.range[2]
      local gap = lines[row + 1]:sub(start_col + 1, end_col)
      local count = math.min(math.max(#gap, spacing.min_spaces), spacing.max_spaces)
      local edit = { start_row = row, start_col = start_col, end_row = row, end_col = end_col, text = (' '):rep(count) }
      if edit.text ~= gap and not read_only.touches(edit) then
        table.insert(edits, edit)
      end
    end
  end
  for _, child in ipairs(block.children) do
    visit(child, lines, rules, values, read_only, edits)
  end
end

--- The edits that give each Gap on one line the spaces its Spacing asks for.
--- A Gap that touches a read-only part keeps its text.
---@param root codestyle.Block
---@param lines string[]
---@param rules codestyle.Rule[]
---@param values codestyle.Values
---@param read_only codestyle.ReadOnly
---@return codestyle.Edit[]
function M.edits(root, lines, rules, values, read_only)
  local edits = {}
  visit(root, lines, rules, values, read_only, edits)
  return edits
end

return M
