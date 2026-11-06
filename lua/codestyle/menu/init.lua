-- The Menu (ADR-0004): a modal dialog of three snacks floats over a dim
-- backdrop, the language list, the Options of one Tab and the Preview. This
-- module opens and closes it and keeps its state; the parts that change for
-- their own reasons are composed in: the windows (`menu.panes`), what they
-- show (`menu.render`), the keys and mouse (`menu.input`), saving and the
-- Save / Discard / Cancel question (`menu.saving`), and the scope, Preset
-- and import actions (`menu.draft_actions`). The Preview follows the Draft.

local draft_actions = require('codestyle.menu.draft_actions')
local general = require('codestyle.general')
local input = require('codestyle.menu.input')
local panes = require('codestyle.menu.panes')
local render = require('codestyle.menu.render')
local repo = require('codestyle.repo')
local saving = require('codestyle.menu.saving')

---@class codestyle.MenuOpts
---@field scope? codestyle.Scope the Code Style to edit; default the one of the current buffer
---@field import? string|true imports a Scheme XML once the Menu is open: this path, or `true` for the repo's `Project.xml` or a path the user gives (ADR-0010)

---@class codestyle.Menu
---@field open fun(opts?: codestyle.MenuOpts) opens the Menu, or focuses it when it is open
---@field close fun()
---@field click_tab fun(index: integer) the winbar's click handler of the Tab strip
---@field help fun() lists the keys of the current pane

---@class codestyle.menu.Deps
---@field registry codestyle.Registry
---@field store codestyle.Store
---@field selector codestyle.Selector
---@field notices codestyle.Notices
---@field preview codestyle.Preview
---@field presets codestyle.Presets
---@field scheme_xml codestyle.SchemeXml
---@field draft fun(scope: codestyle.Scope, root?: string): codestyle.Draft?, codestyle.BrokenFile?

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

--- The language spec as the Menu reads it: a Language Plugin's, or `general`.
---@alias codestyle.menu.Spec { name: string, options: codestyle.OptionSpec[], tabs?: codestyle.Tab[], arrangement?: codestyle.ArrangementSpec }

--- What the Menu's parts share: the open Menu's state and the lookups on it.
---@class codestyle.menu.Context
---@field deps codestyle.menu.Deps
---@field state fun(): codestyle.menu.State? nil while the Menu is closed
---@field spec_of fun(id: string): codestyle.menu.Spec
---@field win_of fun(name: codestyle.menu.PaneName): integer? the pane's window while it is open
---@field item_at_cursor fun(): codestyle.menu.Item? the item of the Options row under the cursor
---@field path_of fun(s: codestyle.menu.State): string the Draft's file, for messages
---@field focus_options fun()
---@field project_xml_found fun(): boolean

local M = {}

vim.api.nvim_set_hl(0, 'CodestyleChanged', { link = 'DiagnosticInfo', default = true })
vim.api.nvim_set_hl(0, 'CodestylePreviewChanged', { link = 'DiffChange', default = true })

--- The winbar calls this when a Tab is clicked: a winbar click names a Vim
--- function, so it reaches the editor's Menu through the instance.
---@param index integer the `minwid` of the click label: the Tab's index
function M.click_tab(index)
  require('codestyle.instance').get().menu.click_tab(index)
end

---@param deps codestyle.menu.Deps
---@return codestyle.Menu
function M.new(deps)
  ---@type codestyle.menu.State?
  local state
  local actions ---@type codestyle.menu.DraftActions

  ---@type codestyle.menu.Context
  local ctx
  ctx = {
    deps = deps,
    state = function()
      return state
    end,
    spec_of = function(id)
      if id == general.id then
        return general
      end
      return deps.registry.get(id) --[[@as codestyle.Spec]]
    end,
    win_of = function(name)
      local win = state and state.layout.wins[name]
      return win and win:win_valid() and win.win or nil
    end,
    item_at_cursor = function()
      local win = ctx.win_of('options')
      return win and state and state.options_view and state.options_view.items[vim.api.nvim_win_get_cursor(win)[1]]
    end,
    path_of = function(s)
      return vim.fn.fnamemodify(deps.store.path(s.draft.scope, s.draft.root), ':~')
    end,
    focus_options = function()
      local win = ctx.win_of('options')
      if win then
        vim.api.nvim_set_current_win(win)
      end
    end,
    project_xml_found = function()
      return actions.project_xml_found()
    end,
  }

  local draw = render.new(ctx)
  local save_dialog = saving.new({ notices = deps.notices, path_of = ctx.path_of })
  local menu ---@type codestyle.Menu
  local mount ---@type fun(draft: codestyle.Draft, place: codestyle.menu.Place)

  --- Takes the Menu down. The layout is closed unless it closed itself.
  ---@param s codestyle.menu.State
  local function unmount(s)
    state = nil
    s.unsubscribe()
    s.preview.detach()
    if not s.layout.closed then
      s.layout:close()
    end
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
        return id, ctx.spec_of(id).name
      end,
      name = function(id)
        return ctx.spec_of(id).name
      end,
      root = function()
        return assert(state).root
      end,
      focus = ctx.focus_options,
      swap = function(draft)
        local s = assert(state)
        unmount(s)
        mount(draft, s)
      end,
      settle = function(after)
        local s = assert(state)
        if s.draft.modified() then
          save_dialog.ask(s, after, function() end)
        else
          after()
        end
      end,
    },
  })

  local keys = input.new(ctx, draw, {
    close = function()
      menu.close()
    end,
    save = function()
      return save_dialog.save(assert(state))
    end,
    actions = actions,
  })

  ---@param draft codestyle.Draft
  ---@param place codestyle.menu.Place
  mount = function(draft, place)
    local s ---@type codestyle.menu.State
    local layout, bufs = panes.new({
      keys = keys.keys,
      on_update = function()
        if state == s and not s.layout.closed then
          draw.options()
          draw.marker(s)
        end
      end,
      on_close = function()
        -- A window of the Menu closed some other way than `q`, such as
        -- `:close`: the changes are asked about, and Cancel opens it again.
        if state == s then
          unmount(s)
          if draft.modified() then
            save_dialog.ask(s, function() end, function()
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
        draw.marker(s)
      end,
    })
    s.unsubscribe = draft.subscribe(function()
      if state == s then
        draw.languages()
        draw.options()
      end
    end)
    state = s

    layout:show()
    draw.languages()
    draw.options()
    draw.show_preview()
    ctx.focus_options()
    vim.api.nvim_create_autocmd('CursorMoved', {
      buffer = bufs.languages,
      callback = function()
        local win = ctx.win_of('languages')
        local item = win and s.languages_view and s.languages_view.items[vim.api.nvim_win_get_cursor(win)[1]]
        if state == s and item and item.language and s.language ~= item.language then
          s.language = item.language
          draw.options()
          draw.show_preview()
        end
      end,
    })
    vim.api.nvim_create_autocmd('CursorMoved', {
      buffer = bufs.options,
      callback = function()
        if state == s and s.query then
          draw.show_preview()
        end
        if state == s then
          draw.highlight_rule()
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
      ctx.focus_options()
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
        save_dialog.ask(s, function()
          if state == s then
            unmount(s)
          end
        end, function() end)
      else
        unmount(s)
      end
    end,
    click_tab = function(index)
      local s = state
      if s then
        s.tab[s.language] = index
        draw.options()
        draw.show_preview()
      end
    end,
    help = keys.help,
  }
  return menu
end

return M
