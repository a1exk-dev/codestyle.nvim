-- PROTOTYPE (throwaway). Variant A: a modal dialog made of floats, like PhpStorm's Settings dialog.
-- Language list | Options with the Tab strip in a fixed, clickable winbar | Preview. Backdrop behind.
local api = vim.api
local state = require("codestyle_proto.state")
local ui = require("codestyle_proto.ui")

local V = { name = "A · Dialog (floats, like PhpStorm)" }
local S = {}

api.nvim_set_hl(0, "CodestyleBackdrop", { bg = "#000000", default = true })

local function layout()
  local W, H = vim.o.columns, vim.o.lines
  local w, h = math.floor(W * 0.94), math.floor(H * 0.80)
  local row, col = math.floor((H - h) / 2) - 2, math.floor((W - w) / 2)
  local lw = 22
  local pw = math.floor((w - lw) * 0.42)
  local ow = w - lw - pw - 6
  local base = { relative = "editor", row = row, height = h, border = "rounded", zindex = 50, style = "minimal" }
  return {
    back = { relative = "editor", row = 0, col = 0, width = W, height = H, style = "minimal", focusable = false, zindex = 40 },
    langs = vim.tbl_extend("force", base, { col = col, width = lw, title = " Code Style " }),
    opts = vim.tbl_extend("force", base, {
      col = col + lw + 2,
      width = ow,
      footer = " <Tab>/<S-Tab> Tab · <C-h>/<C-l> pane · <Space> toggle · <CR> edit · g? help ",
      footer_pos = "center",
    }),
    prev = vim.tbl_extend("force", base, { col = col + lw + ow + 4, width = pw, title = " Preview " }),
  }
end

function _G.CodestyleProtoTab(minwid)
  if S.app then
    S.app.select_tab(minwid)
    V.render()
  end
end

local function tab_winbar(lang, active)
  local parts = {}
  for i, t in ipairs(lang.tabs) do
    local hl = i == active and "%#CodestyleActive#" or "%#CodestyleInactive#"
    parts[#parts + 1] = ("%s%%%d@v:lua.CodestyleProtoTab@ %s %%X"):format(hl, i, t.name)
  end
  return table.concat(parts, "%#WinBar# ") .. "%#WinBar#%=%#Comment# p Set from… "
end

local function focus(delta)
  local order = { S.langs, S.opts, S.prev }
  local cur = api.nvim_get_current_win()
  for i, w in ipairs(order) do
    if w == cur then
      local t = order[math.max(1, math.min(3, i + delta))]
      return api.nvim_set_current_win(t)
    end
  end
  api.nvim_set_current_win(S.opts)
end

local function item_at()
  local row = api.nvim_win_get_cursor(S.opts)[1]
  return S.items[row]
end

function V.render_preview()
  local lang, tab = S.app.lang(), S.app.tab()
  local it = S.items and S.items[api.nvim_win_get_cursor(S.opts)[1]]
  local status = ui.render_preview(S.prev_buf, lang, tab, it and it.def)
  api.nvim_win_set_config(S.prev, { title = " " .. status .. " " })
end

function V.render()
  if not (S.opts and api.nvim_win_is_valid(S.opts)) then
    return
  end
  local app, ctx = S.app, S.app.ctx
  if S.items then
    ctx.cursor = ui.item_key(item_at()) or ctx.cursor
  end
  local lang, tabi = app.lang(), select(2, app.tab())
  local tab = lang.tabs[tabi]

  -- language list
  local b = ui.builder()
  local scope = state.scope_label()
  b:add(" " .. scope, state.scope == "project" and "DiagnosticOk" or "DiagnosticHint"):nl(nil)
  b:add(" [s] switch", "Comment"):nl(nil)
  b:nl(nil)
  S.lang_rows = {}
  for i, l in ipairs(state.data.languages) do
    local n = state.changed_count(l.id)
    b:add(i == ctx.lang and " ▶ " or "   "):add(l.name, i == ctx.lang and "CodestyleGroup" or nil)
    if n > 0 then
      b:pad_to(19):add(("•%d"):format(n), "CodestyleChanged")
    end
    b:nl({ lang = i })
    S.lang_rows[i] = #b.lines
  end
  b:nl(nil)
  for _, k in ipairs(state.data.kept) do
    b:add((" ⚠ %s: not"):format(k.id), "DiagnosticWarn"):nl(nil)
    b:add(("   installed, %d kept"):format(k.count), "DiagnosticWarn"):nl(nil)
  end
  if state.import_offer() then
    b:nl(nil):add(" Project.xml found", "CodestyleBanner"):nl(nil):add(" [i] import", "CodestyleBanner"):nl(nil)
  end
  S.lang_items = b:flush(S.langs_buf)
  if api.nvim_get_current_win() ~= S.langs then
    api.nvim_win_set_cursor(S.langs, { S.lang_rows[ctx.lang], 0 })
  end

  -- options
  local width = api.nvim_win_get_width(S.opts)
  b = ui.builder()
  ui.tab_rows(b, ctx, lang, tab, math.max(30, width - 30))
  S.items = b:flush(S.opts_buf)
  ui.restore_cursor(S.opts, S.items, ctx.cursor, 1)
  vim.wo[S.opts].winbar = tab_winbar(lang, tabi)
  api.nvim_win_set_config(S.opts, { title = (" %s · %s "):format(lang.name, scope), title_pos = "center" })
  V.render_preview()
end

function V.open(app)
  S = { app = app }
  local L = layout()
  S.back_buf = api.nvim_create_buf(false, true)
  vim.bo[S.back_buf].bufhidden = "wipe"
  S.back = api.nvim_open_win(S.back_buf, false, L.back)
  vim.wo[S.back].winhighlight = "Normal:CodestyleBackdrop"
  vim.wo[S.back].winblend = 50

  S.langs_buf, S.opts_buf, S.prev_buf = ui.scratch("languages"), ui.scratch("options"), ui.preview_buf()
  S.langs = api.nvim_open_win(S.langs_buf, false, L.langs)
  S.prev = api.nvim_open_win(S.prev_buf, false, L.prev)
  S.opts = api.nvim_open_win(S.opts_buf, true, L.opts)
  ui.pane_win_opts(S.langs)
  ui.pane_win_opts(S.opts)
  ui.preview_win_opts(S.prev)

  for _, buf in ipairs({ S.langs_buf, S.opts_buf, S.prev_buf }) do
    ui.global_keys(buf, app, { "Variant A: <Tab>/<S-Tab> next/prev Tab (or click it) · <C-h>/<C-l> move between panes" })
    ui.map(buf, "<Tab>", function() app.select_tab(select(2, app.tab()) + 1); V.render() end)
    ui.map(buf, "<S-Tab>", function() app.select_tab(select(2, app.tab()) - 1); V.render() end)
    ui.map(buf, "<C-h>", function() focus(-1) end)
    ui.map(buf, "<C-l>", function() focus(1) end)
    ui.map(buf, "<Esc>", app.close)
  end
  ui.option_keys(S.opts_buf, item_at, app.ctx, V.render)
  ui.map(S.langs_buf, "<CR>", function() focus(1) end)

  S.group = api.nvim_create_augroup("codestyle_proto_a", { clear = true })
  api.nvim_create_autocmd("CursorMoved", {
    group = S.group,
    buffer = S.langs_buf,
    callback = function()
      local it = S.lang_items and S.lang_items[api.nvim_win_get_cursor(S.langs)[1]]
      if it and it.lang and it.lang ~= app.ctx.lang then
        app.select_lang(it.lang)
        V.render()
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
  api.nvim_create_autocmd("VimResized", {
    group = S.group,
    callback = function()
      local l = layout()
      for k, w in pairs({ back = S.back, langs = S.langs, opts = S.opts, prev = S.prev }) do
        if api.nvim_win_is_valid(w) then
          api.nvim_win_set_config(w, l[k])
        end
      end
      V.render()
    end,
  })
  api.nvim_create_autocmd("WinClosed", {
    group = S.group,
    callback = function(ev)
      local w = tonumber(ev.match)
      if (w == S.langs or w == S.opts or w == S.prev) and not S.closing then
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
  for _, w in ipairs({ S.opts, S.langs, S.prev, S.back }) do
    if w and api.nvim_win_is_valid(w) then
      api.nvim_win_close(w, true)
    end
  end
  S = {}
end

return V
