-- The public entry of the Core. Requiring it is cheap: it loads no other
-- module until a function is called.

local M = {}

--- The contract version that Language Plugins declare as `api` (ADR-0007).
M.api = 1

--- Formats a real buffer with its saved Code Style, as one undo step (ADR-0014).
---@param opts? codestyle.FormatOpts
function M.format(opts)
  require('codestyle.instance').get().format(opts)
end

return M
