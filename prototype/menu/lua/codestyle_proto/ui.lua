-- PROTOTYPE (throwaway): pieces that every variant uses (a line builder, the Option rows,
-- the Preview buffer, and the common keymaps). Layout is NOT shared: each variant owns it.
local state = require("codestyle_proto.state")
local widgets = require("codestyle_proto.widgets")
local engine = require("codestyle_proto.engine")

local M = {}
M.ns = vim.api.nvim_create_namespace("codestyle_proto")

vim.api.nvim_set_hl(0, "CodestyleChanged", { link = "DiagnosticInfo", default = true })
vim.api.nvim_set_hl(0, "CodestyleGroup", { link = "Title", default = true })
vim.api.nvim_set_hl(0, "CodestyleActive", { link = "TabLineSel", default = true })
vim.api.nvim_set_hl(0, "CodestyleInactive", { link = "TabLine", default = true })
vim.api.nvim_set_hl(0, "CodestylePreviewChanged", { link = "DiffChange", default = true })
vim.api.nvim_set_hl(0, "CodestyleBanner", { link = "DiagnosticVirtualTextWarn", default = true })

-- Line builder --------------------------------------------------------------

local B = {}
B.__index = B

function M.builder()
  return setmetatable({ lines = {}, marks = {}, items = {}, line = "", segs = {} }, B)
end

function B:add(text, hl)
  if hl and #text > 0 then
    table.insert(self.segs, { #self.line, #self.line + #text, hl })
  end
  self.line = self.line .. text
  return self
end

function B:pad_to(col)
  local w = vim.fn.strdisplaywidth(self.line)
  return self:add(string.rep(" ", math.max(1, col - w)))
end

function B:nl(item)
  table.insert(self.lines, self.line)
  local row = #self.lines - 1
  for _, s in ipairs(self.segs) do
    table.insert(self.marks, { row, s[1], s[2], s[3] })
  end
  self.items[row + 1] = item
  self.line, self.segs = "", {}
  return self
end

function B:flush(buf)
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, self.lines)
  vim.api.nvim_buf_clear_namespace(buf, M.ns, 0, -1)
  for _, m in ipairs(self.marks) do
    vim.api.nvim_buf_set_extmark(buf, M.ns, m[1], m[2], { end_col = m[3], hl_group = m[4] })
  end
  vim.bo[buf].modifiable = false
  return self.items
end

-- Buffers and windows -------------------------------------------------------

function M.scratch(name)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].modifiable = false
  vim.bo[buf].filetype = "codestyle_proto"
  pcall(vim.api.nvim_buf_set_name, buf, "codestyle://" .. name .. "/" .. buf)
  return buf
end

function M.pane_win_opts(win)
  vim.wo[win].number = false
  vim.wo[win].relativenumber = false
  vim.wo[win].signcolumn = "no"
  vim.wo[win].wrap = false
  vim.wo[win].cursorline = true
  vim.wo[win].foldcolumn = "0"
  vim.wo[win].winfixbuf = true
end

-- Option rows ---------------------------------------------------------------

local function item_key(item)
  return item and (item.def and item.def.full or item.group_id) or nil
end
M.item_key = item_key

function M.option_row(b, d, depth, vcol, crumb)
  local en = state.enabled(d)
  local lhl = not en and "Comment" or (state.is_set(d.full) and "CodestyleChanged" or nil)
  b:add(string.rep("  ", depth + (d.indent or 0)))
  if crumb then
    b:add(crumb, "Comment")
  end
  if d.type == "boolean" then
    local txt = widgets.value_text(d)
    b:add(txt .. " ", en and "Special" or "Comment"):add(d.label, lhl)
  else
    b:add("    " .. d.label, lhl):pad_to(vcol)
    local txt, vhl = widgets.value_text(d)
    b:add(txt, en and vhl or "Comment")
  end
  b:nl({ def = d })
end

function M.group_row(b, g, depth, open, vcol, id, crumb)
  b:add(string.rep("  ", depth))
  if crumb then
    b:add(crumb, "Comment")
  end
  b:add((open and "▾ " or "▸ ") .. g.label, "CodestyleGroup")
  if g.option then
    b:pad_to(vcol)
    local txt, vhl = widgets.value_text(g.option)
    b:add(txt, vhl)
  end
  b:nl({ group = g, group_id = id, def = g.option })
end

-- Renders the rows of one Tab. `opts.match` (a lowercase string) keeps only matching Options
-- and flattens the tree with breadcrumbs.
function M.tab_rows(b, ctx, lang, tab, vcol, opts)
  opts = opts or {}
  local function walk(rows, depth, path, crumbs)
    for _, r in ipairs(rows) do
      if r.t == "group" then
        local id = lang.id .. "/" .. tab.name .. "/" .. path .. r.label
        if opts.match then
          if r.option and r.label:lower():find(opts.match, 1, true) then
            M.group_row(b, r, depth, true, vcol, id, crumbs)
          end
          walk(r.children, depth, path .. r.label .. "/", crumbs .. r.label .. " › ")
        else
          local open = ctx.folds[id] ~= false
          M.group_row(b, r, depth, open, vcol, id)
          if open then
            walk(r.children, depth + 1, path .. r.label .. "/", crumbs)
          end
        end
      elseif r.t == "option" then
        if not opts.match then
          M.option_row(b, r, depth, vcol)
        elseif r.label:lower():find(opts.match, 1, true) or r.key:find(opts.match, 1, true) then
          M.option_row(b, r, depth, vcol, crumbs)
        end
      elseif r.t == "note" and not opts.match then
        b:add(string.rep("  ", depth) .. r.label, "Comment"):nl(nil)
      end
    end
  end
  walk(tab.rows, opts.depth or 0, "", opts.crumb or "")
end

function M.restore_cursor(win, items, key, fallback_row)
  if not vim.api.nvim_win_is_valid(win) then
    return
  end
  local buf = vim.api.nvim_win_get_buf(win)
  local n = vim.api.nvim_buf_line_count(buf)
  if key then
    for row = 1, n do
      if item_key(items[row]) == key then
        return vim.api.nvim_win_set_cursor(win, { row, 0 })
      end
    end
  end
  vim.api.nvim_win_set_cursor(win, { math.max(1, math.min(fallback_row or 1, n)), 0 })
end

-- Preview -------------------------------------------------------------------

local last_output = {}

function M.preview_buf()
  local buf = M.scratch("preview")
  vim.bo[buf].filetype = "codestyle_proto_preview"
  return buf
end

function M.preview_win_opts(win)
  M.pane_win_opts(win)
  vim.wo[win].cursorline = false
  vim.wo[win].list = true
  vim.wo[win].listchars = "space:·,tab:→ ,trail:·"
end

-- Returns a short status text for a winbar/title.
function M.render_preview(buf, lang, tab, cursor_def)
  if vim.b[buf].proto_lang ~= lang.id then
    pcall(vim.treesitter.stop, buf)
    vim.bo[buf].syntax = ""
    vim.b[buf].proto_hl = "none"
    if lang.ts and pcall(vim.treesitter.start, buf, lang.ts) then
      vim.b[buf].proto_hl = "treesitter"
    elseif lang.syntax then
      vim.bo[buf].syntax = lang.syntax
      vim.b[buf].proto_hl = "syntax"
    end
    vim.b[buf].proto_lang = lang.id
  end
  local lines
  if not tab.sample then
    lines = { "", "  No Preview for this Tab." }
  else
    local t0 = vim.uv.hrtime()
    lines = engine.format(lang.id, tab.sample, function(k)
      return state.get(lang.id .. "." .. k)
    end)
    vim.b[buf].proto_ms = (vim.uv.hrtime() - t0) / 1e6
  end
  -- Lines that changed with the last value change stay marked until the output changes again.
  local id = lang.id .. "/" .. tab.name
  local prev = last_output[id]
  local rows = {}
  if prev and vim.deep_equal(prev.lines, lines) then
    rows = prev.rows
  elseif prev then
    for i, l in ipairs(lines) do
      if prev.lines[i] ~= l then
        rows[#rows + 1] = i - 1
      end
    end
  end
  last_output[id] = { lines = lines, rows = rows }
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  vim.api.nvim_buf_clear_namespace(buf, M.ns, 0, -1)
  for _, r in ipairs(rows) do
    vim.api.nvim_buf_set_extmark(buf, M.ns, r, 0, { line_hl_group = "CodestylePreviewChanged" })
  end
  local changed = #rows
  local note = ""
  if cursor_def and not engine.is_modelled(lang.id, cursor_def.key) and tab.sample then
    note = " · toy engine ignores this Option"
  end
  return ("Preview · %s · %s%s"):format(vim.b[buf].proto_hl, changed > 0 and (changed .. " lines changed") or "no change", note)
end

-- Keymaps -------------------------------------------------------------------

function M.map(buf, lhs, fn, desc)
  vim.keymap.set("n", lhs, fn, { buffer = buf, nowait = true, silent = true, desc = desc })
end

-- Keys on every pane of every variant.
function M.global_keys(buf, app, extra_help)
  M.map(buf, "]v", function() app.cycle(1) end, "next variant")
  M.map(buf, "[v", function() app.cycle(-1) end, "previous variant")
  M.map(buf, "q", function() app.close() end, "close")
  M.map(buf, "s", state.switch_scope, "Global/Project Code Style")
  M.map(buf, "i", function()
    if state.import_offer() then
      state.import_scheme_xml()
    else
      vim.notify("This repo already has a Project Code Style")
    end
  end, "import Scheme XML")
  M.map(buf, "p", function() M.set_from(app) end, "Set from…")
  M.map(buf, "g?", function()
    vim.notify(table.concat(vim.list_extend({
      "Option rows: <Space> toggle/cycle · <CR> edit (picker/input) · l/h next/prev value · x reset to default",
      "Groups: <CR>/za fold · s Global/Project · p Set from… · i import Scheme XML · ]v/[v variant · q close",
    }, extra_help or {}), "\n"))
  end, "help")
end

function M.set_from(app)
  local lang = app.lang()
  local items = vim.deepcopy(lang.presets or {})
  for _, l in ipairs(state.data.languages) do
    if l.id ~= lang.id and l.id ~= "general" then
      table.insert(items, "Copy from " .. l.name)
    end
  end
  if #items == 0 then
    return vim.notify("No Presets for " .. lang.name)
  end
  vim.ui.select(items, { prompt = "Set from… (" .. lang.name .. ")" }, function(choice)
    if choice then
      vim.notify("PROTOTYPE: would apply " .. choice .. ". How Presets act is the ticket about Presets and \"Set from…\".")
    end
  end)
end

-- Keys on an Option pane. `item_at()` returns the item under the cursor.
function M.option_keys(buf, item_at, ctx, rerender)
  local function act(action)
    return function()
      local it = item_at()
      if not it then
        return
      end
      local folds = action == "fold" or action == "toggle" or action == "edit"
      if it.group and folds and (not it.def or action == "fold") then
        ctx.folds[it.group_id] = ctx.folds[it.group_id] == false
        return rerender()
      end
      if it.def and action ~= "fold" then
        widgets.act(it.def, action)
      end
    end
  end
  M.map(buf, "<Space>", act("toggle"), "toggle / cycle")
  M.map(buf, "<CR>", act("edit"), "edit")
  M.map(buf, "l", act("next"), "next value")
  M.map(buf, "h", act("prev"), "previous value")
  M.map(buf, "x", act("reset"), "reset to default")
  M.map(buf, "za", act("fold"), "fold group")
  M.map(buf, "<2-LeftMouse>", act("toggle"), "toggle")
end

function M.banner_lines(b, width)
  local name, path = state.scope_label()
  b:add(" Editing: "):add(name, state.scope == "project" and "DiagnosticOk" or "DiagnosticHint")
  b:add("  " .. path, "Comment"):nl(nil)
  if state.import_offer() then
    b:add(" .idea/codeStyles/Project.xml found, no .codestyle.json  [i] import  [s] create", "CodestyleBanner"):nl(nil)
  end
end

function M.kept_lines(b)
  for _, k in ipairs(state.data.kept) do
    b:add((" ⚠ %s: not installed, %d kept values"):format(k.id, k.count), "DiagnosticWarn"):nl(nil)
  end
end

return M
