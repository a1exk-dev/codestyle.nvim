-- The Menu's windows (ADR-0004): the snacks layout of the three panes over a
-- dim backdrop, their scratch buffers, the sizes that follow the editor's,
-- and drawing a view model into a pane. What the panes show is `menu.render`'s.

local M = {}

local ns = vim.api.nvim_create_namespace('codestyle.menu')

--- The width of the Menu, as a part of the editor's (ADR-0004 prototype).
local WIDTH = 0.94

--- The width inside the Menu's border.
---@return integer
local function inner_width()
  return math.floor(vim.o.columns * WIDTH) - 2
end

--- The language list is narrower in a narrow editor, so the Options keep room.
---@return integer
local function languages_width()
  return math.min(22, math.floor(inner_width() * 0.25))
end

--- The longest text that fits the Menu's border, so that no Neovim version
--- has to cut it (they cut at different ends).
---@param texts string[] from the longest to the shortest
---@return string
function M.fit(texts)
  for _, text in ipairs(texts) do
    if vim.fn.strdisplaywidth(text) + 2 <= inner_width() then
      return text
    end
  end
  return ''
end

---@return string
local function footer()
  local text = M.fit({
    '<Space>/<CR> edit · x reset · f filter · u undo · <C-s> save · g? keys · q close',
    '<CR> edit · f filter · <C-s> save · g? keys · q close',
    'g? keys · q close',
  })
  return text == '' and '' or ' ' .. text .. ' '
end

--- A scratch buffer for a pane, named `codestyle://<name>`.
---@param name string
---@return integer
function M.scratch(name)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = 'wipe'
  vim.bo[buf].modifiable = false
  vim.api.nvim_buf_set_name(buf, 'codestyle://' .. name)
  return buf
end

--- Draws a view into a pane's buffer.
---@param buf integer
---@param pane codestyle.menu.View
function M.draw(buf, pane)
  local cursors = {} ---@type table<integer, integer[]>
  for _, win in ipairs(vim.fn.win_findbuf(buf)) do
    cursors[win] = vim.api.nvim_win_get_cursor(win)
  end
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, pane.lines)
  vim.bo[buf].modifiable = false
  for win, cursor in pairs(cursors) do
    vim.api.nvim_win_set_cursor(win, { math.min(cursor[1], #pane.lines), cursor[2] })
  end
  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  for _, mark in ipairs(pane.marks) do
    vim.api.nvim_buf_set_extmark(buf, ns, mark.row, mark.start_col, { end_col = mark.end_col, hl_group = mark.group })
  end
end

---@alias codestyle.menu.PaneName 'languages'|'options'|'preview'

---@class codestyle.menu.PanesOpts
---@field keys fun(pane: codestyle.menu.PaneName): table<string, snacks.win.Keys|false> the keys of a pane
---@field on_update fun() after each layout update, such as a resize
---@field on_close fun() when the layout closes, by `q` or some other way

--- The three panes in a hidden layout; `layout:show()` opens them.
---@param opts codestyle.menu.PanesOpts
---@return snacks.layout layout
---@return { languages: integer, options: integer, preview: integer } bufs
function M.new(opts)
  local snacks = require('snacks')
  local bufs = { languages = M.scratch('languages'), options = M.scratch('options'), preview = M.scratch('preview') }
  local pane_wo = { number = false, relativenumber = false, signcolumn = 'no', foldcolumn = '0', wrap = false }
  local wins = {
    languages = snacks.win({
      show = false,
      enter = false,
      buf = bufs.languages,
      keys = opts.keys('languages'),
      wo = vim.tbl_extend('force', pane_wo, { cursorline = true, wrap = true, linebreak = true }),
    }),
    options = snacks.win({
      show = false,
      enter = false,
      buf = bufs.options,
      keys = opts.keys('options'),
      wo = vim.tbl_extend('force', pane_wo, { cursorline = true }),
    }),
    preview = snacks.win({
      show = false,
      enter = false,
      buf = bufs.preview,
      keys = opts.keys('preview'),
      bo = { filetype = 'codestyle_preview' },
      wo = vim.tbl_extend(
        'force',
        pane_wo,
        { list = true, listchars = 'space:·,tab:→ ,trail:·', winbar = ' Preview' }
      ),
    }),
  }
  local layout = snacks.layout.new({
    show = false,
    wins = wins,
    layout = {
      box = 'horizontal',
      width = WIDTH,
      height = 0.8,
      border = 'rounded',
      title = 'Code Style',
      footer = footer(),
      backdrop = 60,
      { win = 'languages', width = languages_width, border = 'right' },
      { win = 'options' },
      {
        win = 'preview',
        width = function()
          return math.floor((inner_width() - languages_width()) * 0.42)
        end,
        border = 'left',
      },
    },
    on_update_pre = function(self)
      self.root.opts.footer = footer()
    end,
    on_update = opts.on_update,
    on_close = opts.on_close,
  })
  return layout, bufs
end

return M
