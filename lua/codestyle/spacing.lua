-- Spacing constructors for the `spacing` rule of Language Plugins (ADR-0007).

--- How many spaces a Gap on one line may hold. A Gap with a line break keeps its text.
---@class codestyle.Spacing
---@field min_spaces integer
---@field max_spaces integer

local M = {}

--- Exactly `count` spaces.
---@param count integer
---@return codestyle.Spacing
function M.spaces(count)
  return { min_spaces = count, max_spaces = count }
end

return M
