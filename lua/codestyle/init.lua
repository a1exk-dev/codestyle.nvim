-- The public entry of the Core. Requiring it is cheap: it loads no other
-- module until a function is called.

local M = {}

--- The contract version that Language Plugins declare as `api` (ADR-0007).
M.api = 1

--- Keeps the user's choices. It has no other side effects.
---@param settings? codestyle.Settings
function M.setup(settings)
  require('codestyle.instance').get().setup(settings)
end

--- A `match(buf)` for a spec: true when the buffer's file name matches one of
--- the globs, as PhpStorm assigns file names to a language (ADR-0015).
---@param globs string[] such as `{ 'phpunit.xml.dist', '*.es6' }`
---@return fun(buf: integer): boolean
function M.match_globs(globs)
  return require('codestyle.selector').match_globs(globs)
end

--- Formats a real buffer with its saved Code Style, as one undo step (ADR-0014).
---@param opts? codestyle.FormatOpts
function M.format(opts)
  require('codestyle.instance').get().format(opts)
end

return M
