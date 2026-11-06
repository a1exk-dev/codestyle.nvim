-- The Format Run (ADR-0002): the one run that formats real buffers, the
-- Preview and `codestyle.testing`. Today it runs the Engine's Spacing pass.

local engine = require('codestyle.engine')

---@class codestyle.FormatRequest
---@field lines string[]
---@field language string the language id
---@field parser string
---@field code_style codestyle.CodeStyle

---@class codestyle.FormatResult
---@field edits codestyle.Edit[] the minimal edits, in text order

---@class codestyle.FormatRun
---@field run fun(request: codestyle.FormatRequest): codestyle.FormatResult

local M = {}

---@param deps { registry: codestyle.Registry }
---@return codestyle.FormatRun
function M.new(deps)
  ---@type codestyle.FormatRun
  return {
    run = function(request)
      local source = table.concat(request.lines, '\n')
      local tree = vim.treesitter.get_string_parser(source, request.parser):parse()[1]
      ---@type codestyle.FormatContext
      local ctx = {
        language = request.language,
        root = tree:root(),
        source = source,
        values = request.code_style.values(request.language),
      }
      local edits = engine.layout(ctx, deps.registry.load(request.language, 'formatter'))
      table.sort(edits, function(a, b)
        return a.start_row < b.start_row or (a.start_row == b.start_row and a.start_col < b.start_col)
      end)
      return { edits = edits }
    end,
  }
end

return M
