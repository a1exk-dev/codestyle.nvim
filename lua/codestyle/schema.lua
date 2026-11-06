-- The Option Schema (ADR-0003): defaults of the Options and the resolved
-- values of one language. It does no I/O.

local M = {}

--- The values of a language: the stored value of each Option, else its default.
---@param spec codestyle.Spec
---@param raw_language table the stored table of the language, `{}` when none
---@return codestyle.Values values nested like the stored keys
---@return string[] problems
function M.resolve(spec, raw_language)
  local values = {}
  for _, option in ipairs(spec.options) do
    local path = vim.split(option.key, '.', { plain = true })
    local value = vim.tbl_get(raw_language, unpack(path))
    if value == nil then
      value = option.default
    end
    local parent = values
    for index = 1, #path - 1 do
      parent[path[index]] = parent[path[index]] or {}
      parent = parent[path[index]]
    end
    parent[path[#path]] = value
  end
  return values, {}
end

return M
