-- PROTOTYPE (throwaway): opens one Menu variant at a time; ]v / [v switch variants.
local state = require("codestyle_proto.state")

local M = {
  variants = {
    require("codestyle_proto.variant_a_dialog"),
    require("codestyle_proto.variant_b_workspace"),
    require("codestyle_proto.variant_c_page"),
  },
  -- Shared between variants, so switching keeps the language, Tab, folds and cursor.
  ctx = { lang = 2, tabs = {}, folds = {}, cursor = nil, filter = nil, tree_open = {} },
  idx = 1,
  current = nil,
}

function M.lang()
  return state.data.languages[M.ctx.lang]
end

function M.tab()
  local lang = M.lang()
  local i = M.ctx.tabs[lang.id] or 1
  return lang.tabs[i], i
end

function M.select_lang(i)
  if i < 1 or i > #state.data.languages then
    return
  end
  M.ctx.lang = i
  M.ctx.cursor = nil
end

function M.select_tab(i)
  local lang = M.lang()
  M.ctx.tabs[lang.id] = (i - 1) % #lang.tabs + 1
  M.ctx.cursor = nil
end

function M.open(i)
  if M.current then
    M.current.close()
  end
  M.idx = i or M.idx
  M.current = M.variants[M.idx]
  state.listeners = {}
  M.current.open(M)
  require("codestyle_proto.switcher").show(M)
end

function M.cycle(delta)
  M.open((M.idx - 1 + delta) % #M.variants + 1)
end

function M.close()
  require("codestyle_proto.switcher").hide()
  if M.current then
    local cur = M.current
    M.current = nil
    cur.close()
  end
  state.listeners = {}
end

vim.api.nvim_create_user_command("CodestyleProto", function(a)
  M.open(tonumber(a.args) or M.idx)
end, { nargs = "?", desc = "PROTOTYPE: open the Menu (variant 1, 2 or 3)" })

return M
