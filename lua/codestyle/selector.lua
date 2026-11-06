-- The Language Selector (ADR-0015): it chooses the Language Plugin and the
-- parser for a buffer. Today it does the filetype step only. Nothing is cached.

---@class codestyle.Choice
---@field language string the language id
---@field parser string

---@class codestyle.NoChoice
---@field reason 'no_claim'
---@field filetype string

---@class codestyle.Selector
---@field choose fun(buf: integer): codestyle.Choice?, codestyle.NoChoice?

local M = {}

---@param deps { registry: codestyle.Registry }
---@return codestyle.Selector
function M.new(deps)
  ---@type codestyle.Selector
  return {
    choose = function(buf)
      local filetype = vim.bo[buf].filetype
      for _, id in ipairs(deps.registry.languages()) do
        local spec = deps.registry.get(id) --[[@as codestyle.Spec]]
        if vim.list_contains(spec.filetypes, filetype) then
          return { language = id, parser = (spec.parsers[filetype] or spec.parsers.default)[1] }
        end
      end
      return nil, { reason = 'no_claim', filetype = filetype }
    end,
  }
end

return M
