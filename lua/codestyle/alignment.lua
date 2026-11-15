-- Alignment constructors for Blocks (ADR-0002, ADR-0007), a port of
-- IntelliJ's `Alignment`. Blocks that share one Alignment object start at the
-- same column, when each is the first of its group on its line.

---@class codestyle.Alignment
---@field backward_shift boolean

local M = {}

--- A new alignment group. Give the same object to every Block of the group.
--- Without backward shift, the group aligns to its first member, and a later
--- member that is already further right stays. With it, every member moves
--- right to the rightmost member's column.
---@param opts? { backward_shift?: boolean }
---@return codestyle.Alignment
function M.new(opts)
  return { backward_shift = (opts or {}).backward_shift == true }
end

return M
