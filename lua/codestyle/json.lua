-- The JSON text of a Code Style file: indented, with keys in a stable order
-- (`version` first, then by name), so that a save gives small diffs (#50).

local M = {}

local INDENT = '  '

---@param a string
---@param b string
---@return boolean
local function key_order(a, b)
  if (a == 'version') ~= (b == 'version') then
    return a == 'version'
  end
  return a < b
end

---@param value any a decoded JSON value: `vim.NIL` for null, an empty object has `vim.empty_dict()`'s metatable
---@param depth integer
---@return string
local function encode(value, depth)
  if type(value) ~= 'table' or value == vim.NIL then
    return vim.json.encode(value)
  end
  local inner = INDENT:rep(depth + 1)
  local items = {} ---@type string[]
  if vim.islist(value) then
    for _, item in ipairs(value) do
      table.insert(items, inner .. encode(item, depth + 1))
    end
    if #items == 0 then
      return '[]'
    end
    return '[\n' .. table.concat(items, ',\n') .. '\n' .. INDENT:rep(depth) .. ']'
  end
  local keys = vim.tbl_keys(value)
  table.sort(keys, key_order)
  for _, key in ipairs(keys) do
    table.insert(items, inner .. vim.json.encode(key) .. ': ' .. encode(value[key], depth + 1))
  end
  if #items == 0 then
    return '{}'
  end
  return '{\n' .. table.concat(items, ',\n') .. '\n' .. INDENT:rep(depth) .. '}'
end

--- The text of a JSON value, with a final newline.
---@param value any
---@return string
function M.encode(value)
  return encode(value, 0) .. '\n'
end

return M
