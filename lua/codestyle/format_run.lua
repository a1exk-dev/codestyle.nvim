-- The Format Run (ADR-0002, ADR-0007): the one run that formats real buffers,
-- the Preview and `codestyle.testing`. It runs the plugin's `before` steps,
-- then the Engine or the plugin's own `format(ctx)`, then the `after` steps,
-- with a new parse before each, and drops plugin edits outside the range.

local engine = require('codestyle.engine')
local read_only = require('codestyle.read_only')
local text = require('codestyle.text')

---@class codestyle.FormatRequest
---@field lines string[]
---@field language string the language id
---@field parser string
---@field code_style codestyle.CodeStyle
---@field range? codestyle.Range the whole lines to format, nil for the whole text

--- A notice for the caller to report through Notices.
---@class codestyle.Notice
---@field level integer a `vim.log.levels` value
---@field scope codestyle.NoticeScope
---@field key string
---@field message string

---@class codestyle.FormatResult
---@field lines string[] the formatted lines
---@field edits codestyle.Edit[] the minimal edits from the request's lines to `lines`, in text order
---@field notices codestyle.Notice[]

---@class codestyle.FormatRun
---@field run fun(request: codestyle.FormatRequest): codestyle.FormatResult

local M = {}

---@param deps { registry: codestyle.Registry }
---@return codestyle.FormatRun
function M.new(deps)
  ---@type codestyle.FormatRun
  return {
    run = function(request)
      local formatter = deps.registry.load(request.language, 'formatter') --[[@as codestyle.Formatter]]
      local values = request.code_style.values(request.language)
      local lines, range = request.lines, request.range
      local notices = {} ---@type codestyle.Notice[]

      ---@return codestyle.FormatContext
      local function context()
        local source = table.concat(lines, '\n')
        return {
          language = request.language,
          parser = request.parser,
          root = vim.treesitter.get_string_parser(source, request.parser):parse()[1]:root(),
          source = source,
          values = values,
          range = range,
        }
      end

      --- Applies edits inside the range, drops the others with a warning, and
      --- moves the end of the range by the lines that the edits add or remove.
      ---@param edits codestyle.Edit[]
      local function apply(edits)
        if range then
          local outside = read_only.new(read_only.outside(range))
          local inside = vim.tbl_filter(function(edit)
            return not outside.touches(edit)
          end, edits)
          if #inside < #edits then
            table.insert(notices, {
              level = vim.log.levels.WARN,
              scope = 'run',
              key = request.language,
              message = ('Language Plugin "%s" changed text outside the range; the change is dropped'):format(
                request.language
              ),
            })
          end
          local end_row = range.end_row
          for _, edit in ipairs(inside) do
            end_row = end_row + #vim.split(edit.text, '\n', { plain = true }) - 1 - (edit.end_row - edit.start_row)
          end
          range = { start_row = range.start_row, end_row = end_row }
          edits = inside
        end
        lines = text.apply(lines, edits)
      end

      for _, step in ipairs(formatter.before or {}) do
        apply(step(context()))
      end
      if formatter.format then
        apply(formatter.format(context()))
      else
        local edits, engine_notices = engine.layout(context(), formatter)
        vim.list_extend(notices, engine_notices)
        apply(edits)
      end
      for _, step in ipairs(formatter.after or {}) do
        apply(step(context()))
      end

      return { lines = lines, edits = text.diff(request.lines, lines), notices = notices }
    end,
  }
end

return M
