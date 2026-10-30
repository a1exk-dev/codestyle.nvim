-- PROTOTYPE (throwaway): how each Core Option type is shown and edited.
local state = require("codestyle_proto.state")

local M = {}

local function choice_index(d, id)
  for i, c in ipairs(d.choices) do
    if c.id == id then
      return i
    end
  end
  return 1
end

function M.value_text(d)
  local v = state.get(d.full)
  if d.type == "boolean" then
    return v and "[x]" or "[ ]", "Special"
  elseif d.type == "integer" then
    if d.inherit and not state.is_set(d.full) then
      return ("Default: %s"):format(tostring(v)), "Comment"
    end
    return ("[ %s ]"):format(tostring(v)), "Number"
  elseif d.type == "choice" then
    local c = d.choices[choice_index(d, v)]
    return ("‹ %s ›"):format(c and c.label or tostring(v)), "Constant"
  elseif d.type == "string" then
    return ('"%s"'):format(v or ""), "String"
  elseif d.type == "order" or d.type == "list" then
    local shown = table.concat(vim.list_slice(v, 1, 3), ", ")
    return ("%s, … (%d) ›"):format(shown, #v), "String"
  end
  return tostring(v), "Normal"
end

local function blocked(d)
  if state.enabled(d) then
    return false
  end
  local dep = state.defs[d.lang .. "." .. d.dep.key]
  vim.notify(("Disabled: turn on %q first"):format(dep and dep.label or d.dep.key), vim.log.levels.WARN)
  return true
end

local function input_integer(d)
  local cur = state.get(d.full)
  local hint = d.inherit and " (empty = inherit General)" or ""
  vim.ui.input({ prompt = ("%s [%d..%d]%s: "):format(d.label, d.min, d.max, hint), default = tostring(cur) }, function(s)
    if s == nil then
      return
    end
    if s == "" and d.inherit then
      return state.set(d.full, nil)
    end
    local n = tonumber(s)
    if not n or n < d.min or n > d.max or n % 1 ~= 0 then
      return vim.notify(("%s: enter a whole number from %d to %d"):format(d.label, d.min, d.max), vim.log.levels.ERROR)
    end
    state.set(d.full, n)
  end)
end

-- An `order` is edited in a small float: one member per line, reorder with `ddp` or <C-j>/<C-k>, confirm with <CR>/q.
local function edit_order(d)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = "wipe"
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, state.get(d.full))
  local h = math.min(#state.get(d.full), vim.o.lines - 8)
  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    width = 40,
    height = h,
    row = math.floor((vim.o.lines - h) / 2),
    col = math.floor((vim.o.columns - 40) / 2),
    border = "rounded",
    title = " " .. d.label .. " ",
    footer = " <C-j>/<C-k> move · <CR> apply · <Esc> cancel ",
    zindex = 150,
  })
  local function move(delta)
    local r = vim.api.nvim_win_get_cursor(win)[1]
    local t = r + delta
    if t < 1 or t > vim.api.nvim_buf_line_count(buf) then
      return
    end
    local a = vim.api.nvim_buf_get_lines(buf, r - 1, r, false)[1]
    local b = vim.api.nvim_buf_get_lines(buf, t - 1, t, false)[1]
    vim.api.nvim_buf_set_lines(buf, math.min(r, t) - 1, math.max(r, t), false, delta > 0 and { b, a } or { a, b })
    vim.api.nvim_win_set_cursor(win, { t, 0 })
  end
  local function apply()
    local lines = vim.tbl_filter(function(l)
      return l ~= ""
    end, vim.api.nvim_buf_get_lines(buf, 0, -1, false))
    local want = vim.deepcopy(d.default)
    table.sort(want)
    local got = vim.deepcopy(lines)
    table.sort(got)
    if not vim.deep_equal(want, got) then
      return vim.notify("Keep every member exactly once: only the order can change", vim.log.levels.ERROR)
    end
    vim.api.nvim_win_close(win, true)
    state.set(d.full, lines)
  end
  local o = { buffer = buf, nowait = true }
  vim.keymap.set("n", "<C-j>", function() move(1) end, o)
  vim.keymap.set("n", "<C-k>", function() move(-1) end, o)
  vim.keymap.set("n", "<CR>", apply, o)
  vim.keymap.set("n", "q", apply, o)
  vim.keymap.set("n", "<Esc>", function() vim.api.nvim_win_close(win, true) end, o)
end

-- action: "toggle" (<Space>), "edit" (<CR>), "next" (l), "prev" (h), "reset" (x)
function M.act(d, action)
  if action == "reset" then
    return state.set(d.full, nil)
  end
  if blocked(d) then
    return
  end
  local v = state.get(d.full)
  if d.type == "boolean" then
    return state.set(d.full, not v)
  elseif d.type == "choice" then
    if action == "edit" then
      return vim.ui.select(d.choices, {
        prompt = d.label .. ":",
        format_item = function(c)
          return (c.id == v and "● " or "  ") .. c.label
        end,
      }, function(c)
        if c then
          state.set(d.full, c.id)
        end
      end)
    end
    local i = choice_index(d, v) + (action == "prev" and -1 or 1)
    i = (i - 1) % #d.choices + 1
    return state.set(d.full, d.choices[i].id)
  elseif d.type == "integer" then
    if action == "next" or action == "prev" then
      local n = math.max(d.min, math.min(d.max, v + (action == "next" and 1 or -1)))
      return state.set(d.full, n)
    end
    return input_integer(d)
  elseif d.type == "string" then
    return vim.ui.input({ prompt = d.label .. ": ", default = v }, function(s)
      if s ~= nil then
        state.set(d.full, s)
      end
    end)
  elseif d.type == "order" or d.type == "list" then
    if action == "edit" or action == "toggle" then
      return edit_order(d)
    end
  end
end

return M
