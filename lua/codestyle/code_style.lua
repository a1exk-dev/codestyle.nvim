-- A Code Style value: the stored file content and the resolved values of
-- each language.

local schema = require('codestyle.schema')

---@class codestyle.StoredFile
---@field version integer
---@field languages? table<string, table>

---@class codestyle.CodeStyle
---@field raw fun(): codestyle.StoredFile the file content as stored
---@field values fun(id: string): codestyle.Values the resolved values of an installed language

local M = {}

---@param raw codestyle.StoredFile
---@param registry codestyle.Registry
---@return codestyle.CodeStyle
function M.new(raw, registry)
  ---@type codestyle.CodeStyle
  return {
    raw = function()
      return raw
    end,
    values = function(id)
      local language = registry.get(id) --[[@as codestyle.Spec]]
      return (schema.resolve(language, (raw.languages or {})[id] or {}))
    end,
  }
end

return M
