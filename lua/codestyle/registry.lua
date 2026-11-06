-- The Language Registry (ADR-0007): it finds the spec of every installed
-- Language Plugin on the runtimepath on first use, and requires a plugin's
-- lazy modules only when they are needed.

---@alias codestyle.SpecPart 'formatter'

---@class codestyle.Registry
---@field languages fun(): string[] the ids of the installed languages, sorted
---@field get fun(id: string): codestyle.Spec?
---@field load fun(id: string, part: codestyle.SpecPart): any the required module that the spec names for `part`

local M = {}

---@return codestyle.Registry
function M.new()
  ---@type table<string, codestyle.Spec>?
  local specs

  local function discover()
    if not specs then
      specs = {}
      for _, path in ipairs(vim.api.nvim_get_runtime_file('lua/codestyle/languages/*.lua', true)) do
        local spec = dofile(path) ---@type codestyle.Spec
        specs[spec.id] = spec
      end
    end
    return specs
  end

  ---@type codestyle.Registry
  return {
    languages = function()
      local ids = vim.tbl_keys(discover())
      table.sort(ids)
      return ids
    end,
    get = function(id)
      return discover()[id]
    end,
    load = function(id, part)
      return require(discover()[id][part])
    end,
  }
end

return M
