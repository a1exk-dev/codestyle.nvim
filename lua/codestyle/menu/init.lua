-- The Menu (ADR-0004): a modal dialog of three snacks floats over a dim
-- backdrop, the language list, the Options of one Tab and the Preview. Each
-- pane is a scratch buffer drawn whole from a view model (`menu.view`); the
-- keys and clicks turn into Draft operations (`menu.edit`), and the Preview
-- follows the Draft. Closing with unsaved changes asks Save / Discard / Cancel.

local code_style = require('codestyle.code_style')
local draft_actions = require('codestyle.menu.draft_actions')
local edit = require('codestyle.menu.edit')
local general = require('codestyle.general')
local repo = require('codestyle.repo')
local view = require('codestyle.menu.view')

---@class codestyle.MenuOpts
---@field scope? codestyle.Scope the Code Style to edit; default the one of the current buffer
---@field import? string|true imports a Scheme XML once the Menu is open: this path, or `true` for the repo's `Project.xml` or a path the user gives (ADR-0010)

---@class codestyle.Menu
---@field open fun(opts?: codestyle.MenuOpts) opens the Menu, or focuses it when it is open
---@field close fun()
---@field click_tab fun(index: integer) the winbar's click handler of the Tab strip
---@field help fun() lists the keys of the current pane

local M = {}

local ns = vim.api.nvim_create_namespace('codestyle.menu')

vim.api.nvim_set_hl(0, 'CodestyleChanged', { link = 'DiagnosticInfo', default = true })
vim.api.nvim_set_hl(0, 'CodestylePreviewChanged', { link = 'DiffChange', default = true })

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
  local text = fit({
    '<Space>/<CR> edit · x reset · f filter · u undo · <C-s> save · g? keys · q close',
    '<CR> edit · f filter · <C-s> save · g? keys · q close',
    'g? keys · q close',
  })
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

--- True when a 0-based byte column is inside a span of a row.
---@param span? codestyle.menu.Span
---@param col integer
---@return boolean
local function inside(span, col)
  return span ~= nil and col >= span.start_col and col < span.end_col
end

---@param deps { registry: codestyle.Registry, store: codestyle.Store, selector: codestyle.Selector, notices: codestyle.Notices, preview: codestyle.Preview, presets: codestyle.Presets, scheme_xml: codestyle.SchemeXml, draft: fun(scope: codestyle.Scope, root?: string): codestyle.Draft?, codestyle.BrokenFile? }
---@return codestyle.Menu
function M.new(deps)
  --- What the Menu shows, kept when the Menu opens again on the same Draft.
  ---@class codestyle.menu.Place
  ---@field language string the current language id
  ---@field tab table<string, integer> the current Tab of each language
  ---@field folded table<string, table<string, true>> the folded Groups of each language
  ---@field query? string the filter of the Options pane
  ---@field root? string the repo root of the buffer that the Menu was opened from

  ---@class codestyle.menu.State: codestyle.menu.Place
  ---@field draft codestyle.Draft
  ---@field preview codestyle.PreviewHandle
  ---@field layout snacks.layout
  ---@field bufs { languages: integer, options: integer, preview: integer }
  ---@field languages_view? codestyle.menu.View
  ---@field options_view? codestyle.menu.View
  ---@field unsubscribe fun()
  ---@field marker? string the Preview's failure marker
  ---@field shown? codestyle.Tab the Tab that the Preview shows

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

  --- The item of the Options row under the cursor.
  ---@return codestyle.menu.Item?
  local function item_at_cursor()
    local win = win_of('options')
    return win and state and state.options_view and state.options_view.items[vim.api.nvim_win_get_cursor(win)[1]]
  end

  ---@param s codestyle.menu.State
  ---@return string
  local function path_of(s)
    return vim.fn.fnamemodify(deps.store.path(s.draft.scope, s.draft.root), ':~')
  end

  local actions ---@type codestyle.menu.DraftActions

  local function render_languages()
    local s = assert(state)
    local entries = vim.tbl_map(function(id)
      return { id = id, name = spec_of(id).name, changed = s.draft.changed(id) }
    end, language_ids())
    s.languages_view = view.languages({
      scope = s.draft.scope,
      languages = entries,
      kept = s.draft.kept_languages(),
      project_xml = actions.project_xml_found(),
    })
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
      tabs = tabs,
      tab = index,
      query = s.query,
      values = s.draft.code_style().values(s.language),
      changed = s.draft.changed_keys(s.language),
      folded = s.folded[s.language] or {},
      width = win and vim.api.nvim_win_get_width(win) or 80,
    })
    draw(s.bufs.options, s.options_view)
    if win then
      vim.wo[win].winbar = s.query
          and ('%%#Search# Filter: %s %%#WinBar# F clears'):format((s.query:gsub('%%', '%%%%')))
        or view.tab_strip(tabs, index, CLICK)
    end
    local scope = s.draft.scope == 'project' and 'Project Code Style' or 'Global Code Style'
    s.layout.root:set_title(
      fit({ ('%s · %s · %s'):format(spec.name, scope, path_of(s)), ('%s · %s'):format(spec.name, scope), spec.name })
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

  --- Shows the current Tab in the Preview; with a filter, the Tab of the
  --- Option under the cursor.
  local function show_preview()
    local s = assert(state)
    local tabs, index = current_tab(s)
    local item = s.query and item_at_cursor()
    local tab = tabs[item and item.tab or index]
    if s.shown ~= tab then
      s.shown = tab
      s.preview.show({ language = s.language, tab = tab })
    end
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

  local function focus_options()
    local win = win_of('options')
    if win then
      vim.api.nvim_set_current_win(win)
    end
  end

  local editor = edit.new({ notices = deps.notices, on_float_close = focus_options })

  --- Acts on the Option of an Options row.
  ---@param item? codestyle.menu.Item
  ---@param action codestyle.menu.Action
  local function act(item, action)
    local s = assert(state)
    if item and item.option then
      editor.act({ draft = s.draft, language = s.language, spec = spec_of(s.language), option = item.option }, action)
    end
  end

  --- Folds or unfolds the Group of an Options row.
  ---@param item? codestyle.menu.Item
  local function fold(item)
    local s = assert(state)
    if item and item.group then
      local folded = s.folded[s.language] or {}
      s.folded[s.language] = folded
      folded[item.group] = not folded[item.group] or nil
      render_options()
    end
  end

  ---@param query? string
  local function filter(query)
    local s = assert(state)
    s.query = query
    render_options()
    local win = win_of('options')
    if win then
      vim.api.nvim_win_set_cursor(win, { 1, 0 })
    end
    show_preview()
  end

  --- Writes the Draft to its file.
  ---@return boolean saved
  local function save()
    local s = assert(state)
    local ok, problem = s.draft.save()
    if ok then
      deps.notices.report(vim.log.levels.INFO, 'always', 'menu', 'saved ' .. path_of(s))
    else
      deps.notices.report(vim.log.levels.ERROR, 'always', 'menu', ('%s was not saved: %s'):format(path_of(s), problem))
    end
    return ok
  end

  --- The mouse position when it is on a row of a pane's text.
  ---@param name 'languages'|'options'|'preview'
  ---@return { line: integer, column: integer }?
  local function mouse_on(name)
    local pos = vim.fn.getmousepos()
    if pos.winid ~= 0 and pos.winid == win_of(name) and pos.line >= 1 then
      return pos
    end
  end

  --- A left click on an Options row, after the press moved the cursor: on a
  --- value control it edits, on a Group arrow it folds; on a label it does
  --- nothing more.
  local function left_click()
    local pos = mouse_on('options')
    local item = pos and state and state.options_view and state.options_view.items[pos.line]
    if not pos or not item then
      return
    end
    local col = pos.column - 1
    if inside(item.arrow, col) then
      fold(item)
    elseif inside(item.control, col) then
      act(item, 'edit')
    end
  end

  --- A right click moves the cursor; on a value control it acts like
  --- `<Space>` (#12). The popup menu never opens in the Menu.
  local function right_click()
    for _, name in ipairs({ 'languages', 'options', 'preview' }) do
      local pos = mouse_on(name)
      if pos then
        local win = assert(win_of(name))
        vim.api.nvim_set_current_win(win)
        vim.api.nvim_win_set_cursor(win, { pos.line, math.max(0, pos.column - 1) })
        local item = name == 'options' and state and state.options_view and state.options_view.items[pos.line]
        if item and inside(item.control, pos.column - 1) then
          act(item, 'toggle')
        end
        return
      end
    end
  end

  local menu ---@type codestyle.Menu

  ---@param action codestyle.menu.Action
  local function on_row(action)
    return function()
      act(item_at_cursor(), action)
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
        assert(state).draft.undo()
      end,
      desc = 'undo',
    },
    {
      '<C-r>',
      function()
        assert(state).draft.redo()
      end,
      desc = 'redo',
    },
    { '<C-s>', save, desc = 'save' },
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
      's',
      function()
        actions.switch_scope()
      end,
      desc = 'switch between Global and Project',
    },
    {
      'p',
      function()
        actions.set_from()
      end,
      desc = 'set from a Preset',
    },
    {
      'i',
      function()
        actions.import()
      end,
      desc = 'import a Scheme XML',
    },
    {
      'R',
      function()
        actions.report()
      end,
      desc = 'the report of the last import',
    },
    { '<RightMouse>', right_click, desc = 'toggle or cycle the clicked value' },
    { '<Space>', on_row('toggle'), desc = 'toggle / cycle', pane = 'options' },
    {
      '<CR>',
      function()
        local item = item_at_cursor()
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
        fold(item_at_cursor())
      end,
      desc = 'fold a Group',
      pane = 'options',
    },
    {
      'f',
      function()
        vim.ui.input({ prompt = 'Filter the Options: ', default = assert(state).query }, function(query)
          if query ~= nil and state then
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
    { '<CR>', focus_options, desc = 'go to the Options', pane = 'languages' },
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
      if (not key.pane or key.pane == pane) and not key[1]:find('Mouse') and not key[1]:find('Release') then
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
      height = math.min(#lines, vim.o.lines - 4),
      zindex = 100,
      backdrop = false,
      enter = true,
      keys = { q = 'close', ['<Esc>'] = 'close', ['g?'] = 'close' },
      on_close = function()
        if state == s then
          focus_options()
        end
      end,
    })
  end

  local mount ---@type fun(draft: codestyle.Draft, place: codestyle.menu.Place)

  --- Takes the Menu down. The layout is closed unless it closed itself.
  ---@param s codestyle.menu.State
  local function unmount(s)
    state = nil
    click_handler = nil
    s.unsubscribe()
    s.preview.detach()
    if not s.layout.closed then
      s.layout:close()
    end
  end

  --- Asks what to do with unsaved changes: Save / Discard / Cancel.
  ---@param s codestyle.menu.State
  ---@param on_closed fun() runs when the changes are saved or discarded
  ---@param on_cancel fun()
  local function ask(s, on_closed, on_cancel)
    vim.ui.select({ 'Save', 'Discard', 'Cancel' }, {
      prompt = ('The Draft has unsaved changes. Save them to %s?'):format(path_of(s)),
    }, function(choice)
      if choice == 'Save' then
        local ok, problem = s.draft.save()
        if ok then
          deps.notices.report(vim.log.levels.INFO, 'always', 'menu', 'saved ' .. path_of(s))
          on_closed()
        else
          deps.notices.report(
            vim.log.levels.ERROR,
            'always',
            'menu',
            ('%s was not saved: %s'):format(path_of(s), problem)
          )
          on_cancel()
        end
      elseif choice == 'Discard' then
        s.draft.discard()
        on_closed()
      else
        on_cancel()
      end
    end)
  end

  actions = draft_actions.new({
    presets = deps.presets,
    scheme_xml = deps.scheme_xml,
    store = deps.store,
    draft = deps.draft,
    notices = deps.notices,
    host = {
      draft = function()
        return state and state.draft
      end,
      language = function()
        local id = assert(state).language
        return id, spec_of(id).name
      end,
      name = function(id)
        return spec_of(id).name
      end,
      root = function()
        return assert(state).root
      end,
      focus = focus_options,
      swap = function(draft)
        local s = assert(state)
        unmount(s)
        mount(draft, s)
      end,
      settle = function(after)
        local s = assert(state)
        if s.draft.modified() then
          ask(s, after, function() end)
        else
          after()
        end
      end,
    },
  })

  ---@param draft codestyle.Draft
  ---@param place codestyle.menu.Place
  mount = function(draft, place)
    local snacks = require('snacks')
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
    local s ---@type codestyle.menu.State
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
        if state == s and not s.layout.closed then
          render_options()
          render_marker(s)
        end
      end,
      on_close = function()
        -- A window of the Menu closed some other way than `q`, such as
        -- `:close`: the changes are asked about, and Cancel opens it again.
        if state == s then
          unmount(s)
          if draft.modified() then
            ask(s, function() end, function()
              mount(draft, s)
            end)
          end
        end
      end,
    })

    -- `preview` and `unsubscribe` follow: both need `s`.
    ---@diagnostic disable-next-line: missing-fields
    s = {
      draft = draft,
      layout = layout,
      bufs = bufs,
      language = place.language,
      tab = place.tab,
      folded = place.folded,
      query = place.query,
      root = place.root,
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
    focus_options()
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
    vim.api.nvim_create_autocmd('CursorMoved', {
      buffer = bufs.options,
      callback = function()
        if state == s and s.query then
          show_preview()
        end
      end,
    })
  end

  ---@param opts? codestyle.MenuOpts
  local function open(opts)
    opts = opts or {}
    if not pcall(require, 'snacks') then
      deps.notices.report(vim.log.levels.ERROR, 'always', 'menu', 'the Menu needs snacks.nvim; install it')
      return
    end
    local path = type(opts.import) == 'string' and opts.import --[[@as string]] or nil
    if state then
      focus_options()
      if opts.import then
        actions.import(path)
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
    mount(draft, { language = choice and choice.language or general.id, tab = {}, folded = {}, root = root })
    if opts.import then
      actions.import(path)
    end
  end

  menu = {
    open = open,
    close = function()
      local s = state
      if not s then
        return
      end
      if s.draft.modified() then
        ask(s, function()
          if state == s then
            unmount(s)
          end
        end, function() end)
      else
        unmount(s)
      end
    end,
    click_tab = M.click_tab,
    help = help,
  }
  return menu
end

return M
