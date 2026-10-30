-- PROTOTYPE (throwaway): the floating variant bar. Not part of any design.
local M = {}
local win, buf

function M.hide()
  if win and vim.api.nvim_win_is_valid(win) then
    vim.api.nvim_win_close(win, true)
  end
  win = nil
end

function M.show(app)
  M.hide()
  local text = ("  ◀ [v   %d/%d  %s   ]v ▶  "):format(app.idx, #app.variants, app.current.name)
  buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = "wipe"
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { text })
  local w = vim.fn.strdisplaywidth(text)
  win = vim.api.nvim_open_win(buf, false, {
    relative = "editor",
    row = vim.o.lines - 4,
    col = math.floor((vim.o.columns - w) / 2),
    width = w,
    height = 1,
    style = "minimal",
    border = "rounded",
    focusable = false,
    zindex = 250,
  })
  vim.wo[win].winhighlight = "Normal:PmenuSel,FloatBorder:PmenuSel"
end

return M
