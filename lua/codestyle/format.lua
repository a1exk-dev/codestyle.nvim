-- The format API (ADR-0014): every entry point formats a real buffer through
-- `format`. It writes only the changed text, as one undo step.

---@class codestyle.FormatOpts
---@field buf? integer the buffer, 0 or nil for the current one
---@field range? integer[] `{ start_line, end_line }`: the whole lines to format, 1-based and inclusive; nil for the whole buffer
---@field arrangement? codestyle.ArrangementMode `force` rearranges also when the language's Arrangement is off; default `auto`

---@class codestyle.FormatApi
---@field format fun(opts?: codestyle.FormatOpts)
--- Formats the lines of the current Visual selection, then ends Visual mode.
--- A charwise selection counts as linewise; a blockwise one is refused.
---@field format_selection fun()
--- True when a Language Plugin claims the buffer, even if its parser is
--- missing. It gives no notice.
---@field claimed fun(buf: integer): boolean
--- True when a Language Plugin claims the buffer and its parser is installed.
--- It gives no notice.
---@field can_format fun(buf: integer): boolean
--- Formats lines that stand for the buffer's text, such as the output of an
--- earlier conform formatter. Returns the new lines, or nil and why not.
---@field format_lines fun(buf: integer, lines: string[], range?: integer[]): string[]?, string?

local repo = require('codestyle.repo')

local M = {}

---@param buf integer
---@param edits codestyle.Edit[] in text order
local function apply(buf, edits)
  for index = #edits, 1, -1 do
    local edit = edits[index]
    vim.api.nvim_buf_set_text(
      buf,
      edit.start_row,
      edit.start_col,
      edit.end_row,
      edit.end_col,
      vim.split(edit.text, '\n', { plain = true })
    )
  end
end

--- Tells the user why a buffer is not formatted. A refused plugin and one
--- whose formatting is off are silent here: the Registry warned once.
---@param notices codestyle.Notices
---@param buf integer
---@param no_choice codestyle.NoChoice
local function report_no_choice(notices, buf, no_choice)
  local warn = vim.log.levels.WARN
  if no_choice.reason == 'no_claim' then
    notices.report(warn, 'run', no_choice.filetype, no_choice.message)
  elseif no_choice.reason == 'conflict' then
    notices.report(warn, 'filetype', no_choice.filetype, no_choice.message)
  elseif no_choice.reason == 'no_parser' then
    notices.report(warn, 'buffer', ('%d:%s'):format(buf, no_choice.language), no_choice.message)
  end
end

---@param deps { notices: codestyle.Notices, selector: codestyle.Selector, store: codestyle.Store, format_run: codestyle.FormatRun }
---@return codestyle.FormatApi
function M.new(deps)
  --- One format run of these lines of the buffer, with its notices.
  ---@param buf integer
  ---@param lines string[]
  ---@param range? integer[]
  ---@param mode? codestyle.ArrangementMode
  ---@return codestyle.FormatResult?
  ---@return string? message why nothing is formatted
  local function run(buf, lines, range, mode)
    deps.notices.begin_run()
    local choice, no_choice = deps.selector.choose(buf)
    if not choice then
      ---@cast no_choice codestyle.NoChoice
      report_no_choice(deps.notices, buf, no_choice)
      return nil, no_choice.message
    end
    local code_style = deps.store.for_buffer(buf)
    if not code_style then
      return nil, 'the Code Style file of this buffer is broken; see the error above'
    end
    local path = vim.api.nvim_buf_get_name(buf)
    local result, failure = deps.format_run.run({
      lines = lines,
      language = choice.language,
      parser = choice.parser,
      code_style = code_style,
      range = range and { start_row = range[1] - 1, end_row = range[2] - 1 },
      path = path ~= '' and path or nil,
      root = repo.root(buf) or vim.fn.getcwd(),
      arrangement = mode,
      buf = buf,
    })
    if not result then
      ---@cast failure codestyle.FormatFailure
      local message = ('Language Plugin "%s" failed; the buffer is unchanged: %s'):format(
        failure.language,
        failure.message
      )
      deps.notices.report(vim.log.levels.ERROR, 'run', failure.language, message)
      return nil, message
    end
    if result.fileformat then
      vim.bo[buf].fileformat = result.fileformat
    end
    for _, notice in ipairs(result.notices) do
      -- A `buffer` notice is once per buffer and its key.
      local key = notice.scope == 'buffer' and ('%d:%s'):format(buf, notice.key) or notice.key
      deps.notices.report(notice.level, notice.scope, key, notice.message)
    end
    return result
  end

  ---@type codestyle.FormatApi
  local api
  api = {
    claimed = function(buf)
      local choice, no_choice = deps.selector.choose(buf)
      return choice ~= nil or (no_choice --[[@as codestyle.NoChoice]]).reason == 'no_parser'
    end,
    format_selection = function()
      local mode = vim.fn.mode()
      local first, last = vim.fn.line('v'), vim.fn.line('.')
      vim.api.nvim_feedkeys(vim.keycode('<Esc>'), 'nx', false)
      if mode == '\22' then
        deps.notices.begin_run()
        deps.notices.report(
          vim.log.levels.WARN,
          'run',
          'blockwise',
          'a blockwise selection cannot be formatted; select whole lines with V'
        )
        return
      end
      api.format({ buf = 0, range = { math.min(first, last), math.max(first, last) } })
    end,
    format = function(opts)
      opts = opts or {}
      local buf = (opts.buf == nil or opts.buf == 0) and vim.api.nvim_get_current_buf() or opts.buf --[[@as integer]]
      local result = run(buf, vim.api.nvim_buf_get_lines(buf, 0, -1, true), opts.range, opts.arrangement)
      if result then
        apply(buf, result.edits)
      end
    end,
    can_format = function(buf)
      return deps.selector.choose(buf) ~= nil
    end,
    format_lines = function(buf, lines, range)
      local result, message = run(buf, lines, range)
      return result and result.lines, message
    end,
  }
  return api
end

return M
