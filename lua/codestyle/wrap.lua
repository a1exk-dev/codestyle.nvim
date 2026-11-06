-- Wrap constructors for Blocks (ADR-0002, ADR-0007), a port of IntelliJ's
-- `Wrap`. Blocks that share one Wrap object form one wrap group: the engine
-- may start a line before each of them when a line passes the right margin.

---@alias codestyle.WrapType
---| 'normal' # wrap if long: a line break before the last member that keeps the line within the margin
---| 'chop_down' # chop down if long: when the group does not fit, a line break before every member

---@class codestyle.Wrap
---@field type codestyle.WrapType
---@field wrap_first boolean whether the first member of the group may wrap too

local M = {}

--- A new wrap group. Give the same object to every Block of the group.
---@param type codestyle.WrapType
---@param opts? { wrap_first?: boolean } `wrap_first` defaults to false, as upstream
---@return codestyle.Wrap
function M.new(type, opts)
  return { type = type, wrap_first = (opts or {}).wrap_first == true }
end

return M
