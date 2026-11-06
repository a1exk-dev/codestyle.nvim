-- The format API (ADR-0014): every entry point formats a real buffer through
-- `format`. It writes only the changed text, as one undo step.

---@class codestyle.FormatOpts
---@field buf? integer the buffer, 0 or nil for the current one

---@class codestyle.FormatApi
---@field format fun(opts?: codestyle.FormatOpts)

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
  ---@type codestyle.FormatApi
  return {
    format = function(opts)
      opts = opts or {}
      local buf = (opts.buf == nil or opts.buf == 0) and vim.api.nvim_get_current_buf() or opts.buf --[[@as integer]]
      deps.notices.begin_run()

      local choice, no_choice = deps.selector.choose(buf)
      if not choice then
        report_no_choice(deps.notices, buf, no_choice --[[@as codestyle.NoChoice]])
        return
      end

      local code_style = deps.store.for_buffer(buf)
      if not code_style then
        return
      end

      local result = deps.format_run.run({
        lines = vim.api.nvim_buf_get_lines(buf, 0, -1, true),
        language = choice.language,
        parser = choice.parser,
        code_style = code_style,
      })
      apply(buf, result.edits)
    end,
  }
end

return M
