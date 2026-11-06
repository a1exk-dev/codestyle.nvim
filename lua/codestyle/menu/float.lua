-- The small floats of the Menu that edit a value with more than one item
-- (ADR-0003, ADR-0004): an `order`, whose members move with `J`/`K`
-- (ADR-0012), and a `list`, whose items are the lines of an editable buffer.
-- `<CR>` applies and `q`/`<Esc>` cancel. Each float is a scratch buffer named
-- `codestyle://order` or `codestyle://list`.

local M = {}

---@class codestyle.menu.FloatOpts
---@field title string
---@field lines string[]
---@field apply fun(lines: string[]): boolean takes the float's lines; false keeps the float open
---@field on_close fun() runs after the float closes, applied or not

--- Opens one float with the keys of its kind.
---@param kind 'order'|'list'
---@param opts codestyle.menu.FloatOpts
---@param keys table<string, fun(win: snacks.win)>
---@param footer string
local function open(kind, opts, keys, footer)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = 'wipe'
  vim.api.nvim_buf_set_name(buf, 'codestyle://' .. kind)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, opts.lines)
  vim.bo[buf].modifiable = kind == 'list'
  local win_keys = {} ---@type table<string, snacks.win.Keys|false>
  for lhs, fn in pairs(keys) do
    win_keys[lhs] = { lhs, fn, mode = 'n', nowait = true }
  end
  require('snacks').win({
    buf = buf,
    title = ' ' .. opts.title .. ' ',
    footer = ' ' .. footer .. ' ',
    border = 'rounded',
    width = math.max(40, vim.fn.strdisplaywidth(opts.title) + 4),
    height = math.max(3, math.min(#opts.lines + 1, vim.o.lines - 8)),
    zindex = 100,
    backdrop = false,
    enter = true,
    wo = { number = false, relativenumber = false, signcolumn = 'no', cursorline = kind == 'order' },
    keys = win_keys,
    on_close = function()
      opts.on_close()
    end,
  })
end

--- The lines of the float's buffer.
---@param win snacks.win
---@return string[]
local function lines_of(win)
  return vim.api.nvim_buf_get_lines(win.buf, 0, -1, false)
end

--- An `order` float: one member per line, `J`/`K` move the member under the
--- cursor down or up.
---@param opts codestyle.menu.FloatOpts
function M.order(opts)
  ---@param delta integer
  local function move(delta)
    return function(win)
      local row = vim.api.nvim_win_get_cursor(win.win)[1]
      local lines = lines_of(win)
      local to = row + delta
      if to < 1 or to > #lines then
        return
      end
      lines[row], lines[to] = lines[to], lines[row]
      vim.bo[win.buf].modifiable = true
      vim.api.nvim_buf_set_lines(win.buf, 0, -1, false, lines)
      vim.bo[win.buf].modifiable = false
      vim.api.nvim_win_set_cursor(win.win, { to, 0 })
    end
  end
  open('order', opts, {
    J = move(1),
    K = move(-1),
    ['<CR>'] = function(win)
      if opts.apply(lines_of(win)) then
        win:close()
      end
    end,
    q = function(win)
      win:close()
    end,
    ['<Esc>'] = function(win)
      win:close()
    end,
  }, 'J/K move · <CR> apply · q cancel')
end

--- A `list` float: one item per line, edited as text; blank lines are left out.
---@param opts codestyle.menu.FloatOpts
function M.list(opts)
  open('list', opts, {
    ['<CR>'] = function(win)
      local items = vim.tbl_filter(function(line)
        return vim.trim(line) ~= ''
      end, vim.tbl_map(vim.trim, lines_of(win)))
      if opts.apply(items) then
        win:close()
      end
    end,
    q = function(win)
      win:close()
    end,
    ['<Esc>'] = function(win)
      win:close()
    end,
  }, 'one item per line · <CR> apply · q cancel')
end

return M
