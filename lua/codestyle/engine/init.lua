-- The Engine (ADR-0002): the IntelliJ Block model. It changes only the Gaps
-- between Blocks. Its interface to the rest of the Core is `layout`.

local spacing = require('codestyle.engine.spacing')

local M = {}

--- The Gap edits for the whole text.
---@param ctx codestyle.FormatContext
---@param formatter codestyle.Formatter
---@return codestyle.Edit[]
function M.layout(ctx, formatter)
  local root = formatter.build(ctx)
  return spacing.edits(root, vim.split(ctx.source, '\n', { plain = true }), formatter.rules, ctx.values)
end

return M
