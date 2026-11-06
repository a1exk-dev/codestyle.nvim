-- The Format Run (ADR-0002, ADR-0007, ADR-0011, ADR-0018): the one run that
-- formats real buffers, the Preview and `codestyle.testing`. It skips a file
-- that Do not format matches, converts mixed line endings, rearranges, then
-- runs the plugin's `before` steps, the Engine or the plugin's own `format(ctx)`, and the
-- `after` steps, with a new parse before each. It drops edits in marker
-- regions and plugin edits outside the range, and at the end removes the
-- trailing blanks of the lines it changed. An error in the plugin's code
-- ends the run as one failure, and the caller decides what the user sees.

local arrangement_step = require('codestyle.arrangement.step')
local do_not_format = require('codestyle.do_not_format')
local engine = require('codestyle.engine')
local language_context = require('codestyle.language_context')
local line_endings = require('codestyle.line_endings')
local markers = require('codestyle.markers')
local read_only = require('codestyle.read_only')
local text = require('codestyle.text')

---@class codestyle.FormatRequest
---@field lines string[]
---@field language string the language id
---@field parser string
---@field code_style codestyle.CodeStyle
---@field range? codestyle.Range the whole lines to format, nil for the whole text
---@field path? string the absolute path of the file, nil when it has none (the Preview)
---@field root? string the folder that Do not format matches `path` from: the repo root or the working directory
---@field arrangement? codestyle.ArrangementMode default `auto`
---@field buf? integer the buffer whose LSP clients Arrangement may ask; nil for the Preview

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
---@field fileformat? 'dos' set when mixed line endings convert to CRLF; `lines` then hold no `\r`
---@field matches codestyle.ArrangementMatch[] the Slot and rule of each rearranged Arrangement Entry, at its row in `lines`

--- A run that the Language Plugin's code ended with an error. The run
--- changes nothing; each caller decides what the user sees.
---@class codestyle.FormatFailure
---@field language string the language id
---@field message string the error that the plugin's code raised

---@class codestyle.FormatRun
---@field run fun(request: codestyle.FormatRequest): codestyle.FormatResult?, codestyle.FormatFailure?

local M = {}

--- The notice of a run that Do not format skips, or nil when no glob matches.
---@param request codestyle.FormatRequest with a `path`
---@param globs string[]
---@return codestyle.Notice?
local function do_not_format_notice(request, globs)
  local path = request.root and vim.fs.relpath(request.root, request.path) or request.path --[[@as string]]
  local glob = do_not_format.match(globs, path)
  return glob
    and {
      level = vim.log.levels.INFO,
      -- The path stands for the buffer: later runs in it are quiet.
      scope = 'buffer',
      key = request.path,
      message = ('"%s" matches the Do not format pattern "%s"; it is not formatted'):format(path, glob),
    }
end

---@param deps { registry: codestyle.Registry }
---@return codestyle.FormatRun
function M.new(deps)
  ---@type codestyle.FormatRun
  return {
    run = function(request)
      local languages = language_context.new({ registry = deps.registry, code_style = request.code_style })
      -- Getting the language loads its formatter: the first call into the
      -- plugin's code.
      local got, language = pcall(languages.get, request.language)
      if not got then
        return nil, { language = request.language, message = tostring(language) }
      end
      ---@cast language codestyle.Language
      local values = language.values
      local notices = {} ---@type codestyle.Notice[]

      local skip = request.path and do_not_format_notice(request, values.general.do_not_format)
      if skip then
        return { lines = request.lines, edits = {}, notices = { skip }, matches = {} }
      end

      local spec = deps.registry.get(request.language) --[[@as codestyle.Spec]]
      local converted, fileformat = line_endings.convert(request.lines)
      local lines = converted
      local range = request.range

      local marker_regions, marker_problem = markers.new(values.general)
      if marker_problem then
        table.insert(
          notices,
          { level = vim.log.levels.WARN, scope = 'session', key = marker_problem, message = marker_problem }
        )
      end

      -- Arrangement ignores markers (ADR-0018), and moves entries in the range
      -- among themselves. It calls the plugins' `entries` and `build`.
      local arranged_ok, arranged = pcall(arrangement_step.run, {
        registry = deps.registry,
        languages = languages,
        code_style = request.code_style,
        lines = lines,
        language = request.language,
        parser = request.parser,
        range = range,
        mode = request.arrangement or 'auto',
        buf = request.buf,
        notices = notices,
      })
      if not arranged_ok then
        return nil, { language = request.language, message = tostring(arranged) }
      end
      lines, range = arranged.lines, arranged.range
      local matches = arranged.matches

      ---@return codestyle.FormatContext
      local function context()
        local source = table.concat(lines, '\n')
        return {
          language = request.language,
          parser = request.parser,
          root = vim.treesitter.get_string_parser(source, request.parser):parse()[1]:root(),
          source = source,
          values = values,
          uses = language.uses,
          range = range,
        }
      end

      --- Drops the edits in marker regions, applies the edits inside the
      --- range, drops the others with a warning, and
      --- moves the end of the range by the lines that the edits add or remove.
      ---@param edits codestyle.Edit[]
      local function apply(edits)
        if marker_regions then
          -- Marker regions are found again in the text of each step, and their
          -- edits are dropped without a notice: the plugin cannot know them.
          local regions = read_only.new(marker_regions.regions(lines, spec.on_marker_in_region))
          edits = vim.tbl_filter(function(edit)
            return not regions.touches(edit)
          end, edits)
        end
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
        for _, match in ipairs(matches) do
          match.row, match.col = text.shift(match.row, match.col, edits)
          match.end_row, match.end_col = text.shift(match.end_row, match.end_col, edits)
        end
        lines = text.apply(lines, edits)
      end

      -- The rest of the plugin's code: its steps, and the engine, which
      -- calls `build`, the rules and the formatters of Embedded Languages.
      local formatter = language.formatter
      local ok, err = pcall(function()
        for _, step in ipairs(formatter.before or {}) do
          apply(step(context()))
        end
        if formatter.format then
          apply(formatter.format(context()))
        else
          local edits, engine_notices = engine.layout(context(), languages)
          vim.list_extend(notices, engine_notices)
          apply(edits)
        end
        for _, step in ipairs(formatter.after or {}) do
          apply(step(context()))
        end
      end)
      if not ok then
        return nil, { language = request.language, message = tostring(err) }
      end

      local keep_key = spec.keep_indents_on_empty_lines
      local keep = keep_key ~= nil and vim.tbl_get(values, unpack(vim.split(keep_key, '.', { plain = true }))) == true
      lines = text.trim_changed(converted, lines, keep)

      return {
        lines = lines,
        edits = text.diff(request.lines, lines),
        notices = notices,
        fileformat = fileformat,
        matches = matches,
      }
    end,
  }
end

return M
