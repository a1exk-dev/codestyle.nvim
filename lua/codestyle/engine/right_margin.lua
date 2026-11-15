-- Named seam (#50): the right margin of a grafted part (ADR-0008). The engine
-- asks only this function for the margin that the Wraps of a grafted Block
-- break at. The HTML map decides the real rule and amends ADR-0008; until
-- then the margin is the host file's, which the source suggests. A test pins
-- this default, so a change shows up as a test diff.

local M = {}

--- The right margin of a grafted Block.
---@param host_margin integer the margin of the Block the part is grafted into
---@param embedded_margin integer the margin of the Embedded Language's own Code Style
---@return integer
function M.of_graft(host_margin, embedded_margin)
  local _ = embedded_margin
  return host_margin
end

return M
