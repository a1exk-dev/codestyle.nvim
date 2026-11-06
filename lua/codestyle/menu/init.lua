-- The Menu (ADR-0004): a modal dialog of three snacks floats over a dim
-- backdrop, the language list, the Options of one Tab and the Preview. Each
-- pane is a scratch buffer drawn whole from a view model (`menu.view`); the
-- keys turn into Draft operations, and the Preview follows the Draft.

local general = require('codestyle.general')
local code_style = require('codestyle.code_style')
local repo = require('codestyle.repo')
local view = require('codestyle.menu.view')

---@class codestyle.MenuOpts
---@field scope? codestyle.Scope the Code Style to edit; default the one of the current buffer

---@class codestyle.Menu
---@field open fun(opts?: codestyle.MenuOpts) opens the Menu, or focuses it when it is open
---@field close fun()
---@field click_tab fun(index: integer) the winbar's click handler of the Tab strip
---@field help fun() lists the keys of the current pane

local M = {}

local ns = vim.api.nvim_create_namespace('codestyle.menu')

vim.api.nvim_set_hl(0, 'CodestyleChanged', { link = 'DiagnosticInfo', default = true })

--- The click handler of the open Menu: winbar clicks call a Vim function by name.
---@type fun(index: integer)?
local click_handler

--- The winbar calls this when a Tab is clicked.
---@param index integer the `minwid` of the click label: the Tab's index
function M.click_tab(index)
  if click_handler then
    click_handler(index)
  end
end

local CLICK = "v:lua.require'codestyle.menu'.click_tab"

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
local function fit(texts)
  for _, text in ipairs(texts) do
    if vim.fn.strdisplaywidth(text) + 2 <= inner_width() then
      return text
    end
  end
  return ''
end

---@return string
local function footer()
  local text = fit({ '<Tab> Tab · <C-h>/<C-l> pane · l/h value · g? keys · q close', 'g? keys · q close' })
  return text == '' and '' or ' ' .. text .. ' '
end

--- A scratch buffer for a pane, named `codestyle://<name>`.
---@param name string
---@return integer
local function scratch(name)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = 'wipe'
  vim.bo[buf].modifiable = false
  vim.api.nvim_buf_set_name(buf, 'codestyle://' .. name)
  return buf
end

--- Draws a view into a pane's buffer.
---@param buf integer
---@param pane codestyle.menu.View
local function draw(buf, pane)
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, pane.lines)
  vim.bo[buf].modifiable = false
  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  for _, mark in ipairs(pane.marks) do
    vim.api.nvim_buf_set_extmark(buf, ns, mark.row, mark.start_col, { end_col = mark.end_col, hl_group = mark.group })
  end
end

--- The next or the previous value of an Option for `l`/`h`; nil when the
--- type has no such step (#11 resolution).
---@param option codestyle.OptionSpec
---@param value any
---@param delta integer 1 or -1
---@return any
local function step_value(option, value, delta)
  if option.type == 'boolean' then
    return not value
  elseif option.type == 'integer' then
    local next_value = value + delta
    if (option.min and next_value < option.min) or (option.max and next_value > option.max) then
      return nil
    end
    return next_value
  elseif option.type == 'choice' then
    local choices = option.choices or {}
    for index, choice in ipairs(choices) do
      if choice.id == value then
        return choices[(index - 1 + delta) % #choices + 1].id
      end
    end
    return choices[1] and choices[1].id
  end
end

---@param deps { registry: codestyle.Registry, store: codestyle.Store, selector: codestyle.Selector, notices: codestyle.Notices, preview: codestyle.Preview, draft: fun(scope: codestyle.Scope, root?: string): codestyle.Draft?, codestyle.BrokenFile? }
---@return codestyle.Menu
function M.new(deps)
  ---@class codestyle.menu.State
  ---@field draft codestyle.Draft
  ---@field preview codestyle.PreviewHandle
  ---@field layout snacks.layout
  ---@field bufs { languages: integer, options: integer, preview: integer }
  ---@field language string the current language id
  ---@field tab table<string, integer> the current Tab of each language
  ---@field languages_view? codestyle.menu.View
  ---@field options_view? codestyle.menu.View
  ---@field unsubscribe fun()
  ---@field marker? string the Preview's failure marker

  ---@type codestyle.menu.State?
  local state

  ---@param id string
  ---@return { name: string, options: codestyle.OptionSpec[], tabs?: codestyle.Tab[] }
  local function spec_of(id)
    if id == general.id then
      return general
    end
    return deps.registry.get(id) --[[@as codestyle.Spec]]
  end

  --- The languages of the list: General, then each installed language.
  ---@return string[]
  local function language_ids()
    return vim.list_extend({ general.id }, code_style.used_languages(deps.registry))
  end

  ---@param s codestyle.menu.State
  ---@return codestyle.Tab[], integer
  local function current_tab(s)
    local tabs = view.tabs(spec_of(s.language))
    local index = math.min(s.tab[s.language] or 1, #tabs)
    return tabs, index
  end

  ---@param name 'languages'|'options'|'preview'
  ---@return integer?
  local function win_of(name)
    local win = state and state.layout.wins[name]
    return win and win:win_valid() and win.win or nil
  end

  local function render_languages()
    local s = assert(state)
    local entries = vim.tbl_map(function(id)
      return { id = id, name = spec_of(id).name, changed = s.draft.changed(id) }
    end, language_ids())
    s.languages_view = view.languages({ scope = s.draft.scope, languages = entries, kept = s.draft.kept_languages() })
    draw(s.bufs.languages, s.languages_view)
    local win = win_of('languages')
    if win and vim.api.nvim_get_current_win() ~= win then
      for row, item in pairs(s.languages_view.items) do
        if item.language == s.language then
          vim.api.nvim_win_set_cursor(win, { row, 0 })
        end
      end
    end
  end

  local function render_options()
    local s = assert(state)
    local spec = spec_of(s.language)
    local tabs, index = current_tab(s)
    local win = win_of('options')
    s.options_view = view.tab_rows({
      spec = spec,
      tab = tabs[index],
      values = s.draft.code_style().values(s.language),
      width = win and vim.api.nvim_win_get_width(win) or 80,
    })
    draw(s.bufs.options, s.options_view)
    if win then
      vim.wo[win].winbar = view.tab_strip(tabs, index, CLICK)
    end
    local path = vim.fn.fnamemodify(deps.store.path(s.draft.scope, s.draft.root), ':~')
    local scope = s.draft.scope == 'project' and 'Project Code Style' or 'Global Code Style'
    s.layout.root:set_title(
      fit({ ('%s · %s · %s'):format(spec.name, scope, path), ('%s · %s'):format(spec.name, scope), spec.name })
    )
  end

  --- The Preview's winbar: its name, or the failure marker (ADR-0016). A
  --- resize resets the window options, so it is drawn again after each.
  ---@param s codestyle.menu.State
  local function render_marker(s)
    local win = s.layout.wins.preview
    if win:win_valid() then
      vim.wo[win.win].winbar = s.marker and ('%#DiagnosticWarn#' .. s.marker) or ' Preview'
    end
  end

  local function show_preview()
    local s = assert(state)
    local tabs, index = current_tab(s)
    s.preview.show({ language = s.language, tab = tabs[index] })
  end

  ---@param id string
  local function select_language(id)
    local s = assert(state)
    if s.language ~= id then
      s.language = id
      render_options()
      show_preview()
    end
  end

  ---@param delta integer
  local function next_tab(delta)
    local s = assert(state)
    local tabs, index = current_tab(s)
    s.tab[s.language] = (index - 1 + delta) % #tabs + 1
    render_options()
    show_preview()
  end

  ---@param delta integer
  local function focus_pane(delta)
    local order = { 'languages', 'options', 'preview' }
    local current = vim.api.nvim_get_current_win()
    local at = 2
    for index, name in ipairs(order) do
      if win_of(name) == current then
        at = index
      end
    end
    local win = win_of(order[math.max(1, math.min(#order, at + delta))])
    if win then
      vim.api.nvim_set_current_win(win)
    end
  end

  ---@param delta integer
  local function step(delta)
    local s = assert(state)
    local win = assert(win_of('options'))
    local item = s.options_view and s.options_view.items[vim.api.nvim_win_get_cursor(win)[1]]
    local option = item and item.option
    if not option then
      return
    end
    local value =
      vim.tbl_get(s.draft.code_style().values(s.language), unpack(vim.split(option.key, '.', { plain = true })))
    local next_value = step_value(option, value, delta)
    if next_value ~= nil then
      s.draft.set(s.language, option.key, next_value)
    end
  end

  local menu ---@type codestyle.Menu

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
      'q',
      function()
        menu.close()
      end,
      desc = 'close',
    },
    {
      '<Esc>',
      function()
        menu.close()
      end,
      desc = 'close',
    },
    {
      'g?',
      function()
        menu.help()
      end,
      desc = 'list the keys',
    },
    {
      'l',
      function()
        step(1)
      end,
      desc = 'next value',
      pane = 'options',
    },
    {
      'h',
      function()
        step(-1)
      end,
      desc = 'previous value',
      pane = 'options',
    },
    {
      '<CR>',
      function()
        focus_pane(1)
      end,
      desc = 'go to the Options',
      pane = 'languages',
    },
  }

  ---@param pane string
  ---@return table<string, snacks.win.Keys|false>
  local function keys_of(pane)
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
  end

  --- The help of the current pane: its keys, as buffer text.
  local function help()
    local s = assert(state)
    local snacks = require('snacks')
    local pane = 'options'
    for _, name in ipairs({ 'languages', 'options', 'preview' }) do
      if win_of(name) == vim.api.nvim_get_current_win() then
        pane = name
      end
    end
    local lines = {}
    for _, key in ipairs(keys) do
      if not key.pane or key.pane == pane then
        table.insert(lines, ('%-8s %s'):format(key[1], key.desc))
      end
    end
    local buf = scratch('help')
    vim.bo[buf].modifiable = true
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.bo[buf].modifiable = false
    snacks.win({
      buf = buf,
      title = 'Keys',
      border = 'rounded',
      width = 40,
      height = #lines,
      zindex = 100,
      backdrop = false,
      enter = true,
      keys = { q = 'close', ['<Esc>'] = 'close', ['g?'] = 'close' },
      on_close = function()
        local win = win_of('options')
        if state == s and win then
          vim.api.nvim_set_current_win(win)
        end
      end,
    })
  end

  ---@param opts? codestyle.MenuOpts
  local function open(opts)
    opts = opts or {}
    local has_snacks, snacks = pcall(require, 'snacks')
    if not has_snacks then
      deps.notices.report(vim.log.levels.ERROR, 'always', 'menu', 'the Menu needs snacks.nvim; install it')
      return
    end
    if state then
      local win = win_of('options')
      if win then
        vim.api.nvim_set_current_win(win)
      end
      return
    end
    local buf = vim.api.nvim_get_current_buf()
    local root = repo.root(buf)
    local scope = opts.scope or ((root and vim.uv.fs_stat(deps.store.path('project', root))) and 'project' or 'global')
    local draft, broken = deps.draft(scope, root)
    if not draft then
      ---@cast broken codestyle.BrokenFile
      deps.notices.report(
        vim.log.levels.ERROR,
        'always',
        'menu',
        ('%s:%d: %s; the Menu cannot open this Code Style'):format(broken.path, broken.line, broken.message)
      )
      return
    end
    local choice = deps.selector.choose(buf)

    local bufs = { languages = scratch('languages'), options = scratch('options'), preview = scratch('preview') }
    local pane_wo = { number = false, relativenumber = false, signcolumn = 'no', foldcolumn = '0', wrap = false }
    local wins = {
      languages = snacks.win({
        show = false,
        enter = false,
        buf = bufs.languages,
        keys = keys_of('languages'),
        wo = vim.tbl_extend('force', pane_wo, { cursorline = true, wrap = true, linebreak = true }),
      }),
      options = snacks.win({
        show = false,
        enter = false,
        buf = bufs.options,
        keys = keys_of('options'),
        wo = vim.tbl_extend('force', pane_wo, { cursorline = true }),
      }),
      preview = snacks.win({
        show = false,
        enter = false,
        buf = bufs.preview,
        keys = keys_of('preview'),
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
      on_update = function()
        if state and state.layout and not state.layout.closed then
          render_options()
          render_marker(state)
        end
      end,
      on_close = function()
        menu.close()
      end,
    })

    local s = {
      draft = draft,
      layout = layout,
      bufs = bufs,
      language = choice and choice.language or general.id,
      tab = {},
    }
    s.preview = deps.preview.attach(draft, {
      buf = bufs.preview,
      status = function(marker)
        s.marker = marker
        render_marker(s)
      end,
    })
    s.unsubscribe = draft.subscribe(function()
      if state == s then
        render_languages()
        render_options()
      end
    end)
    state = s
    click_handler = function(index)
      if state == s then
        s.tab[s.language] = index
        render_options()
        show_preview()
      end
    end

    layout:show()
    render_languages()
    render_options()
    show_preview()
    vim.api.nvim_set_current_win(assert(win_of('options')))
    vim.api.nvim_create_autocmd('CursorMoved', {
      buffer = bufs.languages,
      callback = function()
        local win = win_of('languages')
        local item = win and s.languages_view and s.languages_view.items[vim.api.nvim_win_get_cursor(win)[1]]
        if state == s and item and item.language then
          select_language(item.language)
        end
      end,
    })
  end

  menu = {
    open = open,
    close = function()
      local s = state
      if not s then
        return
      end
      state = nil
      click_handler = nil
      s.unsubscribe()
      s.preview.detach()
      s.layout:close()
    end,
    click_tab = M.click_tab,
    help = help,
  }
  return menu
end

return M
