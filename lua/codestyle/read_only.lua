-- Read-only parts: text that a format run must not change. The Engine keeps
-- every Gap that touches a part. Broken code and the lines outside a range are
-- parts today; formatter markers (ADR-0018) and embedded parts that cannot be
-- formatted (ADR-0008) reuse the same mechanism.

--- A part from `{ start_row, start_col }` to `{ end_row, end_col }`, rows
--- 0-based, end exclusive. A column may be `-1` (before the line) or
--- `math.huge` (after the line).
---@alias codestyle.Part number[]

---@class codestyle.ReadOnly
---@field touches fun(edit: codestyle.Edit): boolean true when the edit would change text of a part

local M = {}

---@param row_a number
---@param col_a number
---@param row_b number
---@param col_b number
---@return boolean
local function before(row_a, col_a, row_b, col_b)
  return row_a < row_b or (row_a == row_b and col_a < col_b)
end

---@param parts codestyle.Part[]
---@return codestyle.ReadOnly
function M.new(parts)
  ---@type codestyle.ReadOnly
  return {
    touches = function(edit)
      for _, part in ipairs(parts) do
        if
          before(edit.start_row, edit.start_col, part[3], part[4])
          and before(part[1], part[2], edit.end_row, edit.end_col)
        then
          return true
        end
      end
      return false
    end,
  }
end

--- Whole lines, their leading indent and an insertion at their start included.
---@param start_row integer
---@param end_row integer
---@return codestyle.Part
function M.lines(start_row, end_row)
  return { start_row, -1, end_row, math.huge }
end

--- The text outside the whole lines of a range. An edit inside the lines,
--- such as one that changes the leading indent of the first line, is free.
---@param range codestyle.Range
---@return codestyle.Part[]
function M.outside(range)
  return {
    { 0, 0, range.start_row, 0 },
    { range.end_row, math.huge, math.huge, math.huge },
  }
end

return M
