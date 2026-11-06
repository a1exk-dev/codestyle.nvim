-- Helpers of the Menu tests (ADR-0004, ADR-0017): a child Neovim with a fixed
-- screen, and ways to find the Menu's panes and read them back as the user
-- sees them. The panes are found by their buffer names, `codestyle://<pane>`.

local H = dofile('tests/helpers.lua')

local M = {}

--- A fresh child for one Menu case, with a fixed screen for the screenshots:
--- size, colour scheme, status line. The backdrop needs 'termguicolors'. HOME
--- is the case's folder, so the Global file shows as
--- `~/xdg/config/nvim/codestyle.json`. `vim.ui.select` and `vim.ui.input`
--- stand for the user's picker: they record each call and answer from
--- `M.answer`.
---@param child codestyle.test.Child
---@param plugins string[]
function M.setup(child, plugins)
  child:setup({ plugins = plugins })
  child.lua(
    [[
      local home = ...
      vim.env.HOME = home
      vim.o.lines, vim.o.columns = 24, 80
      vim.o.termguicolors = true
      vim.cmd.colorscheme('habamax')
      vim.o.statusline = '%<%f %l,%c%V'
      vim.o.laststatus = 2
      vim.o.showmode = false
      vim.o.ruler = false
      vim.opt.shortmess:append('I')

      _G.test_ui = { calls = {}, answers = {} }
      vim.ui.select = function(items, opts, on_choice)
        local shown = vim.tbl_map(function(item)
          return opts.format_item and opts.format_item(item) or tostring(item)
        end, items)
        table.insert(_G.test_ui.calls, { kind = 'select', prompt = opts.prompt, items = shown })
        local answer = table.remove(_G.test_ui.answers, 1)
        for index, text in ipairs(shown) do
          if answer and text:find(answer, 1, true) then
            return on_choice(items[index], index)
          end
        end
        on_choice(nil, nil)
      end
      vim.ui.input = function(opts, on_confirm)
        table.insert(_G.test_ui.calls, { kind = 'input', prompt = opts.prompt, default = opts.default })
        local answer = table.remove(_G.test_ui.answers, 1)
        on_confirm(answer ~= vim.NIL and answer or nil)
      end
    ]],
    { child.paths.root }
  )
end

--- Queues the answers of the next `vim.ui.select`/`vim.ui.input` calls: a
--- select picks the first item that contains the text; `vim.NIL` cancels.
---@param child codestyle.test.Child
---@param answers any[]
function M.answer(child, answers)
  child.lua('vim.list_extend(_G.test_ui.answers, ...)', { answers })
end

--- The `vim.ui` calls since the case began: `{ kind, prompt, items|default }`.
---@param child codestyle.test.Child
---@return table[]
function M.ui_calls(child)
  return child.lua_get('_G.test_ui.calls')
end

--- Lets the child run its scheduled callbacks, such as a queued Preview run.
---@param child codestyle.test.Child
function M.settle(child)
  child.lua('vim.wait(20)')
end

---@param child codestyle.test.Child
function M.open_menu(child)
  child.cmd('Codestyle')
  M.settle(child)
end

--- The window of a Menu pane: `languages`, `options`, `preview`, or a float
--- such as `help` or `order`.
---@param child codestyle.test.Child
---@param name string
---@return integer? win
function M.pane_win(child, name)
  local win = child.lua(
    [[
      local name = ...
      for _, win in ipairs(vim.api.nvim_list_wins()) do
        if vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(win)) == 'codestyle://' .. name then
          return win
        end
      end
    ]],
    { name }
  )
  return win ~= vim.NIL and win or nil
end

---@param child codestyle.test.Child
---@param name string
---@return string[]
function M.pane_lines(child, name)
  return child.api.nvim_buf_get_lines(child.api.nvim_win_get_buf(assert(M.pane_win(child, name))), 0, -1, true)
end

--- The rows of a pane with each run of blanks as one space, so that the
--- column of the values, which follows the pane's width, does not matter.
---@param child codestyle.test.Child
---@param name string
---@return string[]
function M.pane_rows(child, name)
  return vim.tbl_map(function(line)
    return vim.trim(line:gsub('%s+', ' '))
  end, M.pane_lines(child, name))
end

--- Puts the cursor on the row of a pane that holds the text, and focuses the pane.
---@param child codestyle.test.Child
---@param name string
---@param text string
function M.cursor_on(child, name, text)
  local win = assert(M.pane_win(child, name))
  child.api.nvim_set_current_win(win)
  for row, line in ipairs(M.pane_lines(child, name)) do
    if line:find(text, 1, true) then
      child.api.nvim_win_set_cursor(win, { row, 0 })
      M.settle(child)
      return
    end
  end
  error(('no row with "%s" in %s'):format(text, name))
end

--- The winbar of a pane, with the highlight and click items left out.
---@param child codestyle.test.Child
---@param name string
---@return string
function M.winbar_text(child, name)
  local winbar = child.lua_get('vim.wo[...].winbar', { assert(M.pane_win(child, name)) })
  return (winbar:gsub('%%#[^#]*#', ''):gsub('%%%d*@[^@]*@', ''):gsub('%%[X<]', ''))
end

--- Clicks a mouse button on the first screen cell of a pane row that shows the text.
---@param child codestyle.test.Child
---@param button 'left'|'right'
---@param name string
---@param text string
function M.click(child, button, name, text)
  local win = assert(M.pane_win(child, name))
  for row, line in ipairs(M.pane_lines(child, name)) do
    local col = line:find(text, 1, true)
    if col then
      local pos = child.fn.win_screenpos(win)
      local winbar = child.lua_get('vim.wo[...].winbar ~= "" and 1 or 0', { win })
      local screen_col = child.fn.strdisplaywidth(line:sub(1, col - 1))
      child.api.nvim_input_mouse(button, 'press', '', 0, pos[1] - 1 + winbar + row - 1, pos[2] - 1 + screen_col)
      child.api.nvim_input_mouse(button, 'release', '', 0, pos[1] - 1 + winbar + row - 1, pos[2] - 1 + screen_col)
      M.settle(child)
      return
    end
  end
  error(('no row with "%s" in %s'):format(text, name))
end

--- The highlight groups of a pane row's extmarks that cover the text.
---@param child codestyle.test.Child
---@param name string
---@param text string
---@return string[]
function M.groups_at(child, name, text)
  local buf = child.api.nvim_win_get_buf(assert(M.pane_win(child, name)))
  for row, line in ipairs(M.pane_lines(child, name)) do
    local col = line:find(text, 1, true)
    if col then
      return child.lua(
        [[
          local buf, row, col = ...
          local groups = {}
          for _, mark in ipairs(vim.api.nvim_buf_get_extmarks(buf, -1, { row, 0 }, { row, -1 }, { details = true })) do
            local d = mark[4]
            if d.hl_group and mark[3] <= col and (d.end_col or mark[3]) > col then
              table.insert(groups, d.hl_group)
            end
          end
          return groups
        ]],
        { buf, row - 1, col - 1 }
      )
    end
  end
  error(('no row with "%s" in %s'):format(text, name))
end

--- Checks the screen against `tests/screenshots/<name>`. With
--- `CODESTYLE_SKIP_SCREENSHOTS` set (the nightly CI job, whose rendering
--- differs) it compares nothing; the facts of each test still run.
---@param child codestyle.test.Child
---@param name string
function M.screenshot(child, name)
  M.settle(child)
  if vim.env.CODESTYLE_SKIP_SCREENSHOTS then
    return
  end
  MiniTest.expect.reference_screenshot(child.get_screenshot({ redraw = true }), 'tests/screenshots/' .. name)
end

M.levels = H.levels

return M
