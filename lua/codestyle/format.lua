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
        no_choice = no_choice --[[@as codestyle.NoChoice]]
        deps.notices.report(
          vim.log.levels.WARN,
          'run',
          no_choice.filetype,
          ('no Language Plugin claims the filetype "%s"'):format(no_choice.filetype)
        )
        return
      end

      local result = deps.format_run.run({
        lines = vim.api.nvim_buf_get_lines(buf, 0, -1, true),
        language = choice.language,
        parser = choice.parser,
        code_style = (deps.store.for_buffer(buf)),
      })
      apply(buf, result.edits)
    end,
  }
end

return M
