-- PROTOTYPE (throwaway). Variant C: one page, lazy.nvim style. Everything is text in ONE buffer
-- (header, language pills, Tab pills, filter, Options), so `/` finds anything. Preview below.
-- `f` filters the Options of ALL Tabs of the language; the Preview follows the Option under the cursor.
local api = vim.api
local state = require("codestyle_proto.state")
local ui = require("codestyle_proto.ui")

local V = { name = "C · Page (one buffer, pills, filter)" }
local S = {}

local function item_at()
  return S.items[api.nvim_win_get_cursor(S.page)[1]]
end

local function preview_tab()
  local lang = S.app.lang()
  local it = item_at()
  if it and it.tab then
    return lang.tabs[it.tab], it.def
  end
  return S.app.tab(), it and it.def
end

function V.render_preview()
  local tab, def = preview_tab()
  local status = ui.render_preview(S.prev_buf, S.app.lang(), tab, def)
  vim.wo[S.prev].winbar = ("%%#Comment# %s · %s"):format(tab.name, status)
end

local function pills(b, list, hl_active, row_item)
  row_item.pills = {}
  for _, p in ipairs(list) do
    local s = #b.line
    b:add(p.text, p.active and hl_active or "CodestyleInactive")
    table.insert(row_item.pills, { s, #b.line, p.action })
    b:add("  ")
  end
end

function V.render()
  if not (S.page and api.nvim_win_is_valid(S.page)) then
    return
  end
  local app, ctx = S.app, S.app.ctx
  if S.items then
    ctx.cursor = ui.item_key(item_at()) or ctx.cursor
  end
  local lang, tabi = app.lang(), select(2, app.tab())
  local width = api.nvim_win_get_width(S.page)
  local b = ui.builder()

  local name, path = state.scope_label()
  b:add("  Code Style", "CodestyleGroup"):pad_to(math.max(14, width - #name - #path - 14))
  b:add("Editing: "):add(name, state.scope == "project" and "DiagnosticOk" or "DiagnosticHint"):add("  " .. path, "Comment"):nl(nil)
  b:add("  [s] switch scope   [p] Set from…", "Comment")
  if state.import_offer() then
    b:add("   .idea/codeStyles/Project.xml found: [i] import", "CodestyleBanner")
  end
  b:nl(nil):nl(nil)

  local langs, row_item = {}, {}
  for i, l in ipairs(state.data.languages) do
    local n = state.changed_count(l.id)
    langs[#langs + 1] = {
      text = (" %d %s%s "):format(i, l.name, n > 0 and (" •" .. n) or ""),
      active = i == ctx.lang,
      action = function() app.select_lang(i) end,
    }
  end
  b:add("  ")
  pills(b, langs, "CodestyleActive", row_item)
  for _, k in ipairs(state.data.kept) do
    b:add((" ⚠ %s: not installed, %d kept values"):format(k.id, k.count), "DiagnosticWarn")
  end
  b:nl(row_item)

  local tabs, tab_item = {}, {}
  for i, t in ipairs(lang.tabs) do
    tabs[#tabs + 1] = { text = " " .. t.name .. " ", active = i == tabi and not ctx.filter, action = function() app.select_tab(i) end }
  end
  b:add("  ")
  pills(b, tabs, "CodestyleActive", tab_item)
  b:add("H/L", "Comment"):nl(tab_item)

  if ctx.filter then
    b:add("  Filter: "):add(ctx.filter, "Search"):add(("   all Tabs of %s · [f] change · [F] clear"):format(lang.name), "Comment"):nl(nil)
  else
    b:add("  [f] filter the Options of every Tab of " .. lang.name, "Comment"):nl(nil)
  end
  b:add("  " .. string.rep("─", math.max(10, width - 4)), "Comment"):nl(nil)
  S.header_rows = #b.lines

  local vcol = math.max(30, math.min(width - 30, 80))
  if ctx.filter then
    local found = false
    for ti, t in ipairs(lang.tabs) do
      local first = #b.lines + 1
      ui.tab_rows(b, ctx, lang, t, vcol, { match = ctx.filter:lower(), crumb = t.name .. " › ", depth = 1 })
      for r = first, #b.lines do
        if b.items[r] then
          b.items[r].tab = ti
          found = true
        end
      end
    end
    if not found then
      b:add("  No Option matches.", "Comment"):nl(nil)
    end
  else
    ui.tab_rows(b, ctx, lang, lang.tabs[tabi], vcol, { depth = 1 })
  end
  S.items = b:flush(S.page_buf)
  ui.restore_cursor(S.page, S.items, ctx.cursor, S.header_rows + 1)
  V.render_preview()
end

local function click()
  local m = vim.fn.getmousepos()
  if m.winid ~= S.page then
    return
  end
  local it = S.items[m.line]
  if it and it.pills then
    local col = m.column - 1
    for _, p in ipairs(it.pills) do
      if col >= p[1] and col < p[2] then
        p[3]()
        return V.render()
      end
    end
  end
end

function V.open(app)
  S = { app = app }
  vim.cmd("tabnew")
  S.tab = api.nvim_get_current_tabpage()
  local empty = api.nvim_get_current_buf()
  S.page_buf, S.prev_buf = ui.scratch("page"), ui.preview_buf()
  S.page = api.nvim_get_current_win()
  api.nvim_win_set_buf(S.page, S.page_buf)
  pcall(api.nvim_buf_delete, empty, { force = true })
  S.prev = api.nvim_open_win(S.prev_buf, false, { split = "below", win = S.page, height = math.floor(vim.o.lines * 0.4) })
  ui.pane_win_opts(S.page)
  ui.preview_win_opts(S.prev)

  local tab_step = function(d)
    return function()
      app.ctx.filter = nil
      app.select_tab(select(2, app.tab()) + d)
      V.render()
    end
  end
  for _, buf in ipairs({ S.page_buf, S.prev_buf }) do
    ui.global_keys(buf, app, { "Variant C: 1-5 language · H/L Tab · f filter all Tabs · F clear · click pills" })
    for i = 1, #state.data.languages do
      ui.map(buf, tostring(i), function()
        app.select_lang(i)
        V.render()
      end)
    end
    ui.map(buf, "H", tab_step(-1))
    ui.map(buf, "L", tab_step(1))
    ui.map(buf, "f", function()
      vim.ui.input({ prompt = "Filter Options: ", default = app.ctx.filter }, function(s)
        if s == nil then
          return
        end
        app.ctx.filter = s ~= "" and s or nil
        app.ctx.cursor = nil
        V.render()
      end)
    end)
    ui.map(buf, "F", function()
      app.ctx.filter = nil
      V.render()
    end)
  end
  ui.option_keys(S.page_buf, item_at, app.ctx, V.render)
  ui.map(S.page_buf, "<LeftRelease>", click)

  S.group = api.nvim_create_augroup("codestyle_proto_c", { clear = true })
  api.nvim_create_autocmd("CursorMoved", {
    group = S.group,
    buffer = S.page_buf,
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
      pcall(api.nvim_win_close, S.prev, true)
      vim.wo[S.page].winfixbuf = false
      vim.cmd.enew()
    end
  end
  S = {}
end

return V
