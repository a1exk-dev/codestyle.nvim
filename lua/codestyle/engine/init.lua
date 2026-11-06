-- The Engine (ADR-0002): the IntelliJ Block model. It changes only the Gaps
-- between Blocks. Its interface to the rest of the Core is `layout`.

local layout = require('codestyle.engine.layout')

local M = {}

--- The sizes of the Indent kinds when the formatter does not give them, as
--- IntelliJ's defaults.
---@type codestyle.IndentOptions
local default_indent = { size = 4, continuation = 8 }

--- The Gap edits for the whole text.
---@param ctx codestyle.FormatContext
---@param formatter codestyle.Formatter
---@return codestyle.Edit[]
function M.layout(ctx, formatter)
  local root = formatter.build(ctx)
  local values = ctx.values
  local rules = formatter.rules or {}
  return layout.edits(root, vim.split(ctx.source, '\n', { plain = true }), {
    spacing = function(parent, left, right)
      return rules.spacing and rules.spacing(parent, left, right, values)
    end,
    indent = formatter.indent_options and formatter.indent_options(values) or default_indent,
    right_margin = formatter.right_margin and formatter.right_margin(values) or values.general.hard_wrap_at,
  })
end

return M
