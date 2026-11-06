-- What the Menu's panes show (ADR-0004, ADR-0012, ADR-0016): the language
-- list, the rows of the current Tab or the filter, the Tab strip and title,
-- the Preview's marker, and which Tab the Preview formats. Each pane is drawn
-- whole from a view model (`menu.view`, `menu.arrangement_rows`).

local arrangement = require('codestyle.arrangement')
local arrangement_edit = require('codestyle.menu.arrangement_edit')
local arrangement_rows = require('codestyle.menu.arrangement_rows')
local code_style = require('codestyle.code_style')
local general = require('codestyle.general')
local panes = require('codestyle.menu.panes')
local view = require('codestyle.menu.view')

--- The winbar click function of the Tab strip.
local CLICK = "v:lua.require'codestyle.menu'.click_tab"

---@class codestyle.menu.Render
---@field languages fun() draws the language list
---@field options fun() draws the Options pane, its Tab strip and the Menu's title
---@field marker fun(s: codestyle.menu.State) draws the Preview's name or failure marker
---@field show_preview fun() shows the current Tab in the Preview; with a filter, the Tab of the row under the cursor
---@field focus_row fun(wanted: codestyle.menu.ArrangementItem) puts the cursor on that Arrangement row
---@field highlight_rule fun() highlights the entries of the rule under the cursor in the Preview
---@field current_tab fun(s: codestyle.menu.State): codestyle.menu.Tab[], integer

local M = {}

---@param ctx codestyle.menu.Context
---@return codestyle.menu.Render
function M.new(ctx)
  ---@param s codestyle.menu.State
  ---@return codestyle.menu.Tab[], integer
  local function current_tab(s)
    local tabs = view.tabs(ctx.spec_of(s.language))
    local index = math.min(s.tab[s.language] or 1, #tabs)
    return tabs, index
  end

  local function languages()
    local s = assert(ctx.state())
    local entries = vim.tbl_map(function(id)
      return { id = id, name = ctx.spec_of(id).name, changed = s.draft.changed(id) }
    end, vim.list_extend({ general.id }, code_style.used_languages(ctx.deps.registry)))
    s.languages_view = view.languages({
      scope = s.draft.scope,
      languages = entries,
      kept = s.draft.kept_languages(),
      project_xml = ctx.project_xml_found(),
    })
    panes.draw(s.bufs.languages, s.languages_view)
    local win = ctx.win_of('languages')
    if win and vim.api.nvim_get_current_win() ~= win then
      for row, item in pairs(s.languages_view.items) do
        if item.language == s.language then
          vim.api.nvim_win_set_cursor(win, { row, 0 })
        end
      end
    end
  end

  ---@param wanted codestyle.menu.ArrangementItem
  local function focus_row(wanted)
    local s = ctx.state()
    local win = ctx.win_of('options')
    for row, item in pairs(s and s.options_view and s.options_view.items or {}) do
      if win and item.arrangement and vim.deep_equal(item.arrangement, wanted) then
        vim.api.nvim_win_set_cursor(win, { row, 0 })
      end
    end
  end

  local function options()
    local s = assert(ctx.state())
    -- The cursor stays on its Arrangement row when rows above it come or go.
    local before = ctx.item_at_cursor()
    local spec = ctx.spec_of(s.language)
    local tabs, index = current_tab(s)
    local win = ctx.win_of('options')
    local width = win and vim.api.nvim_win_get_width(win) or 80
    if tabs[index].arrangement and not s.query then
      local target = { draft = s.draft, language = s.language, spec = assert(spec.arrangement) }
      local current, problem = arrangement_edit.current(target)
      s.options_view = arrangement_rows.rows({
        spec = target.spec,
        arrangement = current,
        default = arrangement.validate(target.spec, nil),
        problem = problem,
        folded = s.folded[s.language] or {},
        width = width,
      })
    else
      -- The filter finds the fixed rows of the Arrangement Tab too.
      local extra
      if s.query and spec.arrangement then
        local target = { draft = s.draft, language = s.language, spec = spec.arrangement }
        extra = arrangement_rows.rows({
          spec = target.spec,
          arrangement = (arrangement_edit.current(target)),
          default = arrangement.validate(target.spec, nil),
          folded = {},
          width = width,
          query = s.query,
        })
        for _, item in pairs(extra.items) do
          item.tab = #tabs
        end
      end
      s.options_view = view.tab_rows({
        spec = spec,
        tabs = tabs,
        tab = index,
        query = s.query,
        extra = extra,
        values = s.draft.code_style().values(s.language),
        changed = s.draft.changed_keys(s.language),
        folded = s.folded[s.language] or {},
        width = width,
      })
    end
    panes.draw(s.bufs.options, s.options_view)
    if before and before.arrangement then
      focus_row(before.arrangement)
    end
    if win then
      vim.wo[win].winbar = s.query
          and ('%%#Search# Filter: %s %%#WinBar# F clears'):format((s.query:gsub('%%', '%%%%')))
        or view.tab_strip(
          tabs,
          index,
          CLICK,
          s.language ~= general.id and spec.arrangement ~= nil and s.draft.arrangement_changed(s.language)
        )
    end
    local scope = s.draft.scope == 'project' and 'Project Code Style' or 'Global Code Style'
    s.layout.root:set_title(panes.fit({
      ('%s · %s · %s'):format(spec.name, scope, ctx.path_of(s)),
      ('%s · %s'):format(spec.name, scope),
      spec.name,
    }))
  end

  --- A resize resets the window options, so the marker is drawn again after each.
  ---@param s codestyle.menu.State
  local function marker(s)
    local win = s.layout.wins.preview
    if win:win_valid() then
      vim.wo[win.win].winbar = s.marker and ('%#DiagnosticWarn#' .. s.marker) or ' Preview'
    end
  end

  local function show_preview()
    local s = assert(ctx.state())
    local tabs, index = current_tab(s)
    local item = s.query and ctx.item_at_cursor()
    local tab = tabs[item and item.tab or index]
    if s.shown ~= tab then
      s.shown = tab
      s.preview.show({ language = s.language, tab = tab })
    end
  end

  local function highlight_rule()
    local s = assert(ctx.state())
    local item = ctx.item_at_cursor()
    local found = item and item.arrangement and item.arrangement.kind == 'rule' and item.arrangement
    s.preview.highlight(found and { slot = found.slot, rule = found.rule } or nil)
  end

  ---@type codestyle.menu.Render
  return {
    languages = languages,
    options = options,
    marker = marker,
    show_preview = show_preview,
    focus_row = focus_row,
    highlight_rule = highlight_rule,
    current_tab = current_tab,
  }
end

return M
