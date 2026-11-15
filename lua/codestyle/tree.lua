-- Dotted paths in the nested tables of a Code Style file. It does no I/O.

local M = {}

---@param value any
---@return boolean
function M.is_object(value)
  return type(value) == 'table' and not vim.islist(value)
end

--- The value at a path, or nil when a part of the path is missing or not an object.
---@param root any
---@param path string[]
---@return any
function M.get(root, path)
  local node = root
  for _, part in ipairs(path) do
    if not M.is_object(node) then
      return nil
    end
    node = node[part]
  end
  return node
end

--- Sets the value at a path. A missing part, or one that is not an object,
--- becomes an empty object.
---@param root table
---@param path string[]
---@param value any
function M.set(root, path, value)
  local node = root
  for index = 1, #path - 1 do
    if not M.is_object(node[path[index]]) then
      node[path[index]] = {}
    end
    node = node[path[index]]
  end
  node[path[#path]] = value
end

--- Removes the value at a path, and then each object along the path that
--- this left empty. `root` itself stays.
---@param root table
---@param path string[]
function M.remove(root, path)
  local parent = M.get(root, vim.list_slice(path, 1, #path - 1))
  if not M.is_object(parent) or parent[path[#path]] == nil then
    return
  end
  parent[path[#path]] = nil
  for depth = #path - 1, 1, -1 do
    local holder = M.get(root, vim.list_slice(path, 1, depth - 1))
    if next(holder[path[depth]]) ~= nil then
      return
    end
    holder[path[depth]] = nil
  end
end

--- The dotted key as a path.
---@param key string
---@return string[]
function M.path(key)
  return vim.split(key, '.', { plain = true })
end

return M
