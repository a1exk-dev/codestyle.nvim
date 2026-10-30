-- PROTOTYPE (throwaway). Variant B: a workspace in its own tabpage with normal splits.
-- Left: one tree of languages and their Tabs (the operator's sketch). Middle: Options. Right: Preview.
-- Neovim does the resizing, <C-w> moves between panes, and the mouse focuses panes.
local api = vim.api
local state = require("codestyle_proto.state")
local ui = require("codestyle_proto.ui")

local V = { name = "B · Workspace (tabpage + splits, tree)" }
local S = {}

local function tree_open(ctx, lang_i)
  local id = state.data.languages[lang_i].id
  if ctx.tree_open[id] == nil then
    return lang_i == ctx.lang
  end
  return ctx.tree_open[id]
end

local function item_at()
  return S.items[api.nvim_win_get_cursor(S.opts)[1]]
end

function V.render_preview()
  local lang, tab = S.app.lang(), S.app.tab()
  local it = S.items and api.nvim_win_is_valid(S.opts) and S.items[api.nvim_win_get_cursor(S.opts)[1]]
  local status = ui.render_preview(S.prev_buf, lang, tab, it and it.def)
  vim.wo[S.prev].winbar = "%#Comment# " .. status
end

function V.render()
  if not (S.opts and api.nvim_win_is_valid(S.opts)) then
    return
  end
  local app, ctx = S.app, S.app.ctx
  if S.items then
    ctx.cursor = ui.item_key(item_at()) or ctx.cursor
  end
  local lang = app.lang()
  local tabi = select(2, app.tab())

  -- tree
  local b = ui.builder()
  local name, path = state.scope_label()
  b:add(" Code Style", "CodestyleGroup"):nl(nil)
  b:add(" " .. name, state.scope == "project" and "DiagnosticOk" or "DiagnosticHint"):nl(nil)
  b:add(" " .. path, "Comment"):nl(nil)
  b:add(" [s] switch  [p] Set from…", "Comment"):nl(nil)
  if state.import_offer() then
    b:add(" Project.xml found: [i] import", "CodestyleBanner"):nl(nil)
  end
  b:nl(nil)
  local cursor_row
  for li, l in ipairs(state.data.languages) do
    local open = tree_open(ctx, li)
    local n = state.changed_count(l.id)
    b:add(open and " ▾ " or " ▸ "):add(l.name, li == ctx.lang and "CodestyleGroup" or nil)
    if n > 0 then
      b:add(("  •%d"):format(n), "CodestyleChanged")
    end
    b:nl({ lang = li })
    if open then
      for ti, t in ipairs(l.tabs) do
        local active = li == ctx.lang and ti == tabi
        b:add("   │ ", "Comment"):add(t.name, active and "CodestyleActive" or nil):nl({ lang = li, tab = ti })
        if active then
          cursor_row = #b.lines
        end
      end
    end
  end
  b:nl(nil)
  ui.kept_lines(b)
  S.tree_items = b:flush(S.tree_buf)
  if cursor_row and api.nvim_get_current_win() ~= S.tree then
    api.nvim_win_set_cursor(S.tree, { cursor_row, 0 })
  end

  -- options
  local width = api.nvim_win_get_width(S.opts)
  b = ui.builder()
  ui.tab_rows(b, ctx, lang, lang.tabs[tabi], math.max(30, width - 30))
  S.items = b:flush(S.opts_buf)
  ui.restore_cursor(S.opts, S.items, ctx.cursor, 1)
  vim.wo[S.opts].winbar = ("%%#CodestyleGroup# %s › %s %%#Comment#%%= ]t/[t Tab · g? help ")
    :format(lang.name, lang.tabs[tabi].name)
  V.render_preview()
end

local function activate_tree_row(move_focus)
  local it = S.tree_items[api.nvim_win_get_cursor(S.tree)[1]]
  if not it then
    return
  end
  local ctx = S.app.ctx
  if it.tab then
    if it.lang ~= ctx.lang then
      S.app.select_lang(it.lang)
    end
    S.app.select_tab(it.tab)
    V.render()
    if move_focus then
      api.nvim_set_current_win(S.opts)
    end
  else
    local id = state.data.languages[it.lang].id
    ctx.tree_open[id] = not tree_open(ctx, it.lang)
    V.render()
  end
end

function V.open(app)
  S = { app = app }
  vim.cmd("tabnew")
  S.tab = api.nvim_get_current_tabpage()
  local empty = api.nvim_get_current_buf()
  S.tree_buf, S.opts_buf, S.prev_buf = ui.scratch("tree"), ui.scratch("options"), ui.preview_buf()
  S.opts = api.nvim_get_current_win()
  api.nvim_win_set_buf(S.opts, S.opts_buf)
  pcall(api.nvim_buf_delete, empty, { force = true })
  S.tree = api.nvim_open_win(S.tree_buf, false, { split = "left", win = S.opts, width = 32 })
  S.prev = api.nvim_open_win(S.prev_buf, false, { split = "right", win = S.opts, width = math.floor(vim.o.columns * 0.4) })
  ui.pane_win_opts(S.tree)
  ui.pane_win_opts(S.opts)
  ui.preview_win_opts(S.prev)
  vim.wo[S.tree].winfixwidth = true

  local next_tab = function(d)
    return function()
      app.select_tab(select(2, app.tab()) + d)
      V.render()
    end
  end
  for _, buf in ipairs({ S.tree_buf, S.opts_buf, S.prev_buf }) do
    ui.global_keys(buf, app, { "Variant B: <C-w>h/l between panes · ]t/[t next/prev Tab · tree: <CR> open, moving the cursor previews" })
    ui.map(buf, "]t", next_tab(1))
    ui.map(buf, "[t", next_tab(-1))
  end
  ui.option_keys(S.opts_buf, item_at, app.ctx, V.render)
  ui.map(S.tree_buf, "<CR>", function() activate_tree_row(true) end)
  ui.map(S.tree_buf, "<Space>", function() activate_tree_row(false) end)
  ui.map(S.tree_buf, "<LeftRelease>", function() activate_tree_row(false) end)

  S.group = api.nvim_create_augroup("codestyle_proto_b", { clear = true })
  api.nvim_create_autocmd("CursorMoved", {
    group = S.group,
    buffer = S.tree_buf,
    callback = function()
      local it = S.tree_items and S.tree_items[api.nvim_win_get_cursor(S.tree)[1]]
      local ctx = app.ctx
      if it and it.tab and (it.lang ~= ctx.lang or it.tab ~= select(2, app.tab())) then
        activate_tree_row(false)
      end
    end,
  })
  api.nvim_create_autocmd("CursorMoved", {
    group = S.group,
    buffer = S.opts_buf,
    callback = function()
      app.ctx.cursor = ui.item_key(item_at())
      V.render_preview()
    end,
  })
  api.nvim_create_autocmd("WinResized", { group = S.group, callback = vim.schedule_wrap(V.render) })
  api.nvim_create_autocmd("TabClosed", {
    group = S.group,
    callback = function()
      if not api.nvim_tabpage_is_valid(S.tab) and not S.closing then
        vim.schedule(app.close)
      end
    end,
  })
  state.on_change(V.render)
  V.render()
  api.nvim_set_current_win(S.opts)
end

function V.close()
  S.closing = true
  if S.group then
    pcall(api.nvim_del_augroup_by_id, S.group)
  end
  if S.tab and api.nvim_tabpage_is_valid(S.tab) then
    if #api.nvim_list_tabpages() > 1 then
      vim.cmd.tabclose(api.nvim_tabpage_get_number(S.tab))
    else
      for _, w in ipairs({ S.tree, S.prev }) do
        pcall(api.nvim_win_close, w, true)
      end
      vim.wo[S.opts].winfixbuf = false
      vim.cmd.enew()
    end
  end
  S = {}
end

return V
