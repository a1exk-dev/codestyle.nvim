-- PROTOTYPE (throwaway): in-memory Code Style values. Nothing is written to disk.
local data = require("codestyle_proto.data")

local M = {
  data = data,
  defs = {}, -- "<lang>.<key>" -> option definition
  scopes = { global = {}, project = nil },
  scope = "global",
  listeners = {},
  last_changed = nil,
}

local function index(lang, rows)
  for _, r in ipairs(rows) do
    local opt = r.t == "option" and r or r.option
    if opt then
      opt.full = lang.id .. "." .. opt.key
      opt.lang = lang.id
      M.defs[opt.full] = opt
    end
    if r.children then
      index(lang, r.children)
    end
  end
end

for _, lang in ipairs(data.languages) do
  for _, tab in ipairs(lang.tabs) do
    index(lang, tab.rows)
  end
end

local function values()
  return M.scopes[M.scope]
end

function M.get(full)
  local d = M.defs[full]
  if not d then
    return nil
  end
  local v = values()[full]
  if v ~= nil then
    return v
  end
  if d.inherit then
    return M.get(d.inherit)
  end
  return d.default
end

function M.is_set(full)
  return values()[full] ~= nil
end

function M.set(full, v)
  local d = M.defs[full]
  if v ~= nil and not d.inherit and vim.deep_equal(v, d.default) then
    v = nil
  end
  values()[full] = v
  M.last_changed = full
  M.emit()
end

function M.enabled(d)
  if not d.dep then
    return true
  end
  return M.get(d.lang .. "." .. d.dep.key) == d.dep.is
end

function M.changed_count(lang_id)
  local n = 0
  for full in pairs(values()) do
    if full:sub(1, #lang_id + 1) == lang_id .. "." then
      n = n + 1
    end
  end
  return n
end

function M.on_change(fn)
  table.insert(M.listeners, fn)
end

function M.emit()
  for _, fn in ipairs(M.listeners) do
    fn()
  end
end

function M.scope_label()
  if M.scope == "global" then
    return "Global Code Style", vim.fn.fnamemodify(vim.fn.stdpath("config"), ":~") .. "/codestyle.json"
  end
  return "Project Code Style", vim.fn.fnamemodify(vim.fn.getcwd(), ":~") .. "/.codestyle.json"
end

-- The prototype pretends that the repo has .idea/codeStyles/Project.xml.
function M.import_offer()
  return M.scopes.project == nil
end

function M.import_scheme_xml()
  M.scopes.project = {
    ["php.space_before_method_call_parentheses"] = true,
    ["php.class_brace_style"] = "end_of_line",
    ["php.method_brace_style"] = "end_of_line",
    ["php.indent_size"] = 2,
  }
  M.scope = "project"
  vim.notify("PROTOTYPE: imported .idea/codeStyles/Project.xml into a new Project Code Style (4 values)")
  M.emit()
end

function M.switch_scope()
  if M.scope == "project" then
    M.scope = "global"
    return M.emit()
  end
  if M.scopes.project then
    M.scope = "project"
    return M.emit()
  end
  vim.ui.select({
    "Copy the Global Code Style",
    "Start from the defaults",
    "Import .idea/codeStyles/Project.xml",
  }, { prompt = "No .codestyle.json in this repo. Create a Project Code Style:" }, function(_, idx)
    if idx == 1 then
      M.scopes.project = vim.deepcopy(M.scopes.global)
    elseif idx == 2 then
      M.scopes.project = {}
    elseif idx == 3 then
      return M.import_scheme_xml()
    else
      return
    end
    M.scope = "project"
    M.emit()
  end)
end

return M
