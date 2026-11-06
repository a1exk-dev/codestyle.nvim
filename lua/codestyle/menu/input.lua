-- The Menu's keys and mouse (the #11 resolution, #12, ADR-0006, ADR-0010,
-- ADR-0012): each key of a pane, the clicks on the Options pane, and the
-- `g?` help that lists them. They turn into Draft operations through
-- `menu.edit` and `menu.arrangement_edit`, or into Menu moves.

local arrangement_edit = require('codestyle.menu.arrangement_edit')
local edit = require('codestyle.menu.edit')
local panes = require('codestyle.menu.panes')

--- What the keys do to the Menu as a whole.
---@class codestyle.menu.InputHost
---@field close fun()
---@field save fun(): boolean
---@field actions codestyle.menu.DraftActions

---@class codestyle.menu.Input
---@field keys fun(pane: codestyle.menu.PaneName): table<string, snacks.win.Keys|false> the snacks keys of a pane
---@field help fun() lists the keys of the current pane in a float

local M = {}

--- True when a 0-based byte column is inside a span of a row.
---@param span? codestyle.menu.Span
---@param col integer
---@return boolean
local function inside(span, col)
  return span ~= nil and col >= span.start_col and col < span.end_col
end

---@param ctx codestyle.menu.Context
---@param render codestyle.menu.Render
---@param host codestyle.menu.InputHost
---@return codestyle.menu.Input
function M.new(ctx, render, host)
  local function redraw()
    render.options()
    render.show_preview()
  end

  ---@param delta integer
  local function next_tab(delta)
    local s = assert(ctx.state())
    local tabs, index = render.current_tab(s)
    s.tab[s.language] = (index - 1 + delta) % #tabs + 1
    redraw()
  end

  ---@param delta integer
  local function focus_pane(delta)
    local order = { 'languages', 'options', 'preview' }
    local current = vim.api.nvim_get_current_win()
    local at = 2
    for index, name in ipairs(order) do
      if ctx.win_of(name) == current then
        at = index
      end
    end
    local win = ctx.win_of(order[math.max(1, math.min(#order, at + delta))])
    if win then
      vim.api.nvim_set_current_win(win)
    end
  end

  local editor = edit.new({ notices = ctx.deps.notices, on_float_close = ctx.focus_options })
  local arrangement_editor = arrangement_edit.new({ notices = ctx.deps.notices, on_float_close = ctx.focus_options })

  --- Acts on the Option of an Options row, or on a row of the Arrangement Tab.
  ---@param item? codestyle.menu.Item
  ---@param action codestyle.menu.ArrangementAction
  local function act(item, action)
    local s = assert(ctx.state())
    if item and item.option then
      if vim.list_contains({ 'toggle', 'edit', 'next', 'prev', 'reset' }, action) then
        editor.act(
          { draft = s.draft, language = s.language, spec = ctx.spec_of(s.language), option = item.option },
          action --[[@as codestyle.menu.Action]]
        )
      end
    elseif item and item.arrangement then
      local spec = assert(ctx.spec_of(s.language).arrangement)
      local target = { draft = s.draft, language = s.language, spec = spec }
      local focus = arrangement_editor.act(target, item.arrangement, action)
      if focus and ctx.state() == s then
        render.focus_row(focus)
        render.highlight_rule()
      end
    end
  end

  --- Folds or unfolds the Group of an Options row.
  ---@param item? codestyle.menu.Item
  local function fold(item)
    local s = assert(ctx.state())
    if item and item.group then
      local folded = s.folded[s.language] or {}
      s.folded[s.language] = folded
      folded[item.group] = not folded[item.group] or nil
      render.options()
    end
  end

  ---@param query? string
  local function filter(query)
    local s = assert(ctx.state())
    s.query = query
    render.options()
    local win = ctx.win_of('options')
    if win then
      vim.api.nvim_win_set_cursor(win, { 1, 0 })
    end
    render.show_preview()
  end

  --- The mouse position when it is on a row of a pane's text.
  ---@param name codestyle.menu.PaneName
  ---@return { line: integer, column: integer }?
  local function mouse_on(name)
    local pos = vim.fn.getmousepos()
    if pos.winid ~= 0 and pos.winid == ctx.win_of(name) and pos.line >= 1 then
      return pos
    end
  end

  --- The item of a row of the Options pane.
  ---@param row integer
  ---@return codestyle.menu.Item?
  local function options_item(row)
    local s = ctx.state()
    return s and s.options_view and s.options_view.items[row]
  end

  --- A left click on an Options row, after the press moved the cursor: on a
  --- value control it edits, on a Group arrow it folds; on a label it does
  --- nothing more.
  local function left_click()
    local pos = mouse_on('options')
    local item = pos and options_item(pos.line)
    if not pos or not item then
      return
    end
    local col = pos.column - 1
    if inside(item.arrow, col) then
      fold(item)
    elseif inside(item.control, col) then
      local kind = item.arrangement and item.arrangement.kind
      act(item, (kind == 'enabled' or kind == 'keep' or kind == 'sort') and 'toggle' or 'edit')
    end
  end

  --- A right click moves the cursor; on a value control it acts like
  --- `<Space>` (#12). The popup menu never opens in the Menu.
  local function right_click()
    for _, name in ipairs({ 'languages', 'options', 'preview' }) do
      local pos = mouse_on(name)
      if pos then
        local win = assert(ctx.win_of(name))
        vim.api.nvim_set_current_win(win)
        vim.api.nvim_win_set_cursor(win, { pos.line, math.max(0, pos.column - 1) })
        local item = name == 'options' and options_item(pos.line)
        if item and inside(item.control, pos.column - 1) then
          act(item, 'toggle')
        end
        return
      end
    end
  end

  local help ---@type fun()

  ---@param action codestyle.menu.ArrangementAction
  local function on_row(action)
    return function()
      act(ctx.item_at_cursor(), action)
    end
  end

  --- The keys of every pane, then the keys of each pane, with their help text.
  ---@type { [1]: string, [2]: fun(), desc: string, pane?: string }[]
  local keys = {
    {
      '<Tab>',
      function()
        next_tab(1)
      end,
      desc = 'next Tab',
    },
    {
      '<S-Tab>',
      function()
        next_tab(-1)
      end,
      desc = 'previous Tab',
    },
    {
      '<C-h>',
      function()
        focus_pane(-1)
      end,
      desc = 'pane to the left',
    },
    {
      '<C-l>',
      function()
        focus_pane(1)
      end,
      desc = 'pane to the right',
    },
    {
      'u',
      function()
        assert(ctx.state()).draft.undo()
      end,
      desc = 'undo',
    },
    {
      '<C-r>',
      function()
        assert(ctx.state()).draft.redo()
      end,
      desc = 'redo',
    },
    {
      '<C-s>',
      function()
        host.save()
      end,
      desc = 'save',
    },
    {
      'q',
      function()
        host.close()
      end,
      desc = 'close',
    },
    {
      '<Esc>',
      function()
        host.close()
      end,
      desc = 'close',
    },
    {
      'g?',
      function()
        help()
      end,
      desc = 'list the keys',
    },
    {
      's',
      function()
        host.actions.switch_scope()
      end,
      desc = 'switch between Global and Project',
    },
    {
      'p',
      function()
        host.actions.set_from()
      end,
      desc = 'set from a Preset',
    },
    {
      'i',
      function()
        host.actions.import()
      end,
      desc = 'import a Scheme XML',
    },
    {
      'R',
      function()
        host.actions.report()
      end,
      desc = 'the report of the last import',
    },
    { '<RightMouse>', right_click, desc = 'toggle or cycle the clicked value' },
    { '<Space>', on_row('toggle'), desc = 'toggle / cycle', pane = 'options' },
    {
      '<CR>',
      function()
        local item = ctx.item_at_cursor()
        if item and item.group and not item.option then
          fold(item)
        else
          act(item, 'edit')
        end
      end,
      desc = 'edit / fold',
      pane = 'options',
    },
    { 'l', on_row('next'), desc = 'next value', pane = 'options' },
    { 'h', on_row('prev'), desc = 'previous value', pane = 'options' },
    { 'x', on_row('reset'), desc = 'reset to the default', pane = 'options' },
    {
      'za',
      function()
        fold(ctx.item_at_cursor())
      end,
      desc = 'fold a Group',
      pane = 'options',
    },
    {
      'f',
      function()
        vim.ui.input({ prompt = 'Filter the Options: ', default = assert(ctx.state()).query }, function(query)
          if query ~= nil and ctx.state() then
            query = vim.trim(query)
            filter(query ~= '' and query or nil)
          end
        end)
      end,
      desc = 'filter every Tab',
      pane = 'options',
    },
    {
      'F',
      function()
        filter(nil)
      end,
      desc = 'clear the filter',
      pane = 'options',
    },
    { '<LeftRelease>', left_click, desc = 'edit the clicked value', pane = 'options' },
    { 'X', on_row('reset_all'), desc = 'reset the whole Arrangement', pane = 'options' },
    { 'o', on_row('add_slot'), desc = 'add a rule in a new Slot below / an alias', pane = 'options' },
    { 'a', on_row('add_rule'), desc = 'add a rule to this Slot', pane = 'options' },
    { 'J', on_row('down'), desc = 'move the rule down', pane = 'options' },
    { 'K', on_row('up'), desc = 'move the rule up', pane = 'options' },
    { 'gJ', on_row('slot_down'), desc = 'move the Slot down', pane = 'options' },
    { 'gK', on_row('slot_up'), desc = 'move the Slot up', pane = 'options' },
    { 'dd', on_row('delete'), desc = 'delete the rule / alias', pane = 'options' },
    { 'r', on_row('rename'), desc = 'rename the alias', pane = 'options' },
    { '<CR>', ctx.focus_options, desc = 'go to the Options', pane = 'languages' },
  }

  --- Lists the keys of the current pane in a float; closing it goes back to the Options.
  help = function()
    local s = assert(ctx.state())
    local pane = 'options'
    for _, name in ipairs({ 'languages', 'options', 'preview' }) do
      if ctx.win_of(name) == vim.api.nvim_get_current_win() then
        pane = name
      end
    end
    local lines = {}
    for _, key in ipairs(keys) do
      if (not key.pane or key.pane == pane) and not key[1]:find('Mouse') and not key[1]:find('Release') then
        table.insert(lines, ('%-8s %s'):format(key[1], key.desc))
      end
    end
    local buf = panes.scratch('help')
    vim.bo[buf].modifiable = true
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.bo[buf].modifiable = false
    require('snacks').win({
      buf = buf,
      title = 'Keys',
      border = 'rounded',
      width = 40,
      height = math.min(#lines, vim.o.lines - 4),
      zindex = 100,
      backdrop = false,
      enter = true,
      keys = { q = 'close', ['<Esc>'] = 'close', ['g?'] = 'close' },
      on_close = function()
        if ctx.state() == s then
          ctx.focus_options()
        end
      end,
    })
  end

  ---@type codestyle.menu.Input
  return {
    keys = function(pane)
      local result = {} ---@type table<string, snacks.win.Keys|false>
      for _, key in ipairs(keys) do
        if not key.pane or key.pane == pane then
          local fn = key[2]
          result[key[1]] = {
            key[1],
            function()
              fn()
            end,
            desc = key.desc,
          }
        end
      end
      return result
    end,
    help = help,
  }
end

return M
