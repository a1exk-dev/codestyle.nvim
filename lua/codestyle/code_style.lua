-- A Code Style value: the stored file content and the resolved values of
-- `general` and of each installed language.

local general = require('codestyle.general')
local schema = require('codestyle.schema')

---@class codestyle.StoredFile
---@field version integer
---@field languages? table<string, table>

--- An invalid stored value of one language.
---@class codestyle.LanguageProblem: codestyle.Problem
---@field language string the language id, `general` included

---@class codestyle.CodeStyle
---@field raw fun(): codestyle.StoredFile the file content as stored, after migrations
---@field values fun(id: string): codestyle.Values the resolved values of an installed language, with `general` under `general`
---@field problems fun(): codestyle.LanguageProblem[] the invalid stored values of `general` and of every installed language

local M = {}

---@param raw codestyle.StoredFile
---@param registry codestyle.Registry
---@return codestyle.CodeStyle
function M.new(raw, registry)
  local languages = raw.languages or {}
  ---@type table<string, { values: codestyle.Values, problems: codestyle.Problem[] }>
  local resolved = {}

  ---@param id string
  local function resolve(id)
    if not resolved[id] then
      local general_values = id ~= general.id and resolve(general.id).values or nil
      local spec = id == general.id and general or registry.get(id) --[[@as codestyle.Spec]]
      local values, problems = schema.resolve(spec, languages[id], general_values)
      if general_values then
        values.general = general_values
      end
      resolved[id] = { values = values, problems = problems }
    end
    return resolved[id]
  end

  ---@type codestyle.CodeStyle
  return {
    raw = function()
      return raw
    end,
    values = function(id)
      return resolve(id).values
    end,
    problems = function()
      local problems = {} ---@type codestyle.LanguageProblem[]
      for _, id in ipairs({ general.id, unpack(registry.languages()) }) do
        for _, problem in ipairs(resolve(id).problems) do
          table.insert(problems, { language = id, key = problem.key, message = problem.message })
        end
      end
      return problems
    end,
  }
end

return M
