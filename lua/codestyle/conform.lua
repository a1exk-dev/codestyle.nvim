-- The conform.nvim adapter (ADR-0014): when conform is loaded, the Core adds
-- the `codestyle` formatter to `require('conform').formatters`. It never edits
-- `formatters_by_ft`, and it keeps a `codestyle` entry that the user defined.

---@class codestyle.ConformAdapter
--- Adds the formatter when conform is loaded. It can run any number of times.
---@field register fun()

local M = {}

--- conform's `ctx.range` as whole lines, 1-based and inclusive.
---@param range? { start: integer[], ['end']: integer[] }
---@return integer[]?
local function lines_of(range)
  return range and { range.start[1], range['end'][1] }
end

---@param deps { format_api: codestyle.FormatApi }
---@return codestyle.ConformAdapter
function M.new(deps)
  local format_api = deps.format_api

  ---@type codestyle.ConformAdapter
  return {
    register = function()
      local conform = package.loaded.conform
      if not conform or conform.formatters.codestyle then
        return
      end
      conform.formatters.codestyle = {
        meta = {
          url = 'https://github.com/a1exk-dev/codestyle.nvim',
          description = 'Formats with the PhpStorm-style Code Style of codestyle.nvim.',
        },
        condition = function(_, ctx)
          return format_api.can_format(ctx.buf)
        end,
        format = function(_, ctx, lines, callback)
          local new_lines, message = format_api.format_lines(ctx.buf, lines, lines_of(ctx.range))
          callback(message, new_lines)
        end,
      }
    end,
  }
end

return M
