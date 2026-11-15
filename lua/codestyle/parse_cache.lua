-- The Preview's parse cache (#50 module 13, ADR-0016): between two runs of
-- the Preview most texts do not change (the sample itself, and often the
-- text after each step), so a run reuses the trees of the run before it. A
-- tree is never changed after its parse, so sharing it is safe. Plugins stay
-- pure: they only get the root of a tree, as without the cache.

---@class codestyle.ParseCache
--- The root of the text's tree, parsed now or kept from this run or the run before.
---@field parse fun(source: string, parser: string): TSNode
--- Starts a new run: the trees that the last run used are kept, the others dropped.
---@field next_run fun()

local M = {}

--- Parses the text with no cache.
---@param source string
---@param parser string
---@return TSNode
function M.parse(source, parser)
  return vim.treesitter.get_string_parser(source, parser):parse()[1]:root()
end

---@return codestyle.ParseCache
function M.new()
  ---@type table<string, TSNode>
  local previous, current = {}, {}

  ---@type codestyle.ParseCache
  return {
    parse = function(source, parser)
      local key = parser .. '\0' .. source
      local root = current[key] or previous[key] or M.parse(source, parser)
      current[key] = root
      return root
    end,
    next_run = function()
      previous, current = current, {}
    end,
  }
end

return M
