-- Migrations (ADR-0007): a Language Plugin's renames of keys and of choice
-- ids, applied when a file is read. They are idempotent and need no stored
-- version. A value moves only when the new key is not set; otherwise the old
-- key stays in the file untouched, as an unknown key.

local M = {}

---@param value any
---@return boolean
local function is_object(value)
  return type(value) == 'table' and not vim.islist(value)
end

--- The object that holds the last part of a dotted key, created when
--- `create` is set; nil when a part of the path is not an object.
---@param root table
---@param path string[]
---@param create? boolean
---@return table?
local function parent_of(root, path, create)
  local node = root
  for index = 1, #path - 1 do
    if node[path[index]] == nil and create then
      node[path[index]] = {}
    end
    node = node[path[index]]
    if not is_object(node) then
      return nil
    end
  end
  return node
end

--- Removes the objects along a dotted key that the move left empty.
---@param root table
---@param path string[]
local function prune(root, path)
  for depth = #path - 1, 1, -1 do
    local parent = parent_of(root, vim.list_slice(path, 1, depth))
    if not parent or next(parent[path[depth]]) ~= nil then
      return
    end
    parent[path[depth]] = nil
  end
end

---@param raw_language table
---@param migration codestyle.Migration
local function rename_key(raw_language, migration)
  local from = vim.split(migration.key, '.', { plain = true })
  local to = vim.split(migration.to, '.', { plain = true })
  local old_parent = parent_of(raw_language, from)
  if not old_parent or old_parent[from[#from]] == nil then
    return
  end
  local new_parent = parent_of(raw_language, to)
  if new_parent and new_parent[to[#to]] ~= nil then
    return
  end
  new_parent = parent_of(raw_language, to, true)
  if not new_parent then
    return
  end
  new_parent[to[#to]] = old_parent[from[#from]]
  old_parent[from[#from]] = nil
  prune(raw_language, from)
end

---@param raw_language table
---@param migration codestyle.Migration
local function rename_choice(raw_language, migration)
  local path = vim.split(migration.key, '.', { plain = true })
  local parent = parent_of(raw_language, path)
  if parent and parent[path[#path]] == migration.choice then
    parent[path[#path]] = migration.to
  end
end

--- The stored table of a language with its plugin's migrations applied, in order.
---@param migrations codestyle.Migration[]
---@param raw_language any the stored table of the language
---@return any raw_language a migrated copy; anything that is not an object is returned as is
function M.apply(migrations, raw_language)
  if not is_object(raw_language) then
    return raw_language
  end
  local migrated = vim.deepcopy(raw_language)
  for _, migration in ipairs(migrations) do
    if migration.choice then
      rename_choice(migrated, migration)
    else
      rename_key(migrated, migration)
    end
  end
  return migrated
end

return M
