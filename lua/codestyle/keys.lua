-- The default key (ADR-0014): `<leader>cf` maps to `<Plug>(codestyle-format)`
-- in Normal and Visual mode, unless the key is already mapped or the user set
-- `setup{ keys = false }`.

---@class codestyle.Keys
--- Maps the default key, or removes the Core's own mapping when the settings
--- turn keys off. It can run any number of times.
---@field apply fun()

local M = {}

local lhs = '<leader>cf'
local rhs = '<Plug>(codestyle-format)'
local modes = { 'n', 'x' }

---@param deps { settings: fun(): codestyle.Settings }
---@return codestyle.Keys
function M.new(deps)
  --- The modes where the Core mapped the key. A mapping made by anyone else
  --- is never touched.
  ---@type table<string, true>
  local ours = {}

  ---@type codestyle.Keys
  return {
    apply = function()
      local on = deps.settings().keys ~= false
      for _, mode in ipairs(modes) do
        if on and vim.fn.maparg(lhs, mode) == '' then
          vim.keymap.set(mode, lhs, rhs, { desc = 'codestyle.nvim: format' })
          ours[mode] = true
        elseif not on and ours[mode] and vim.fn.maparg(lhs, mode) == rhs then
          vim.keymap.del(mode, lhs)
          ours[mode] = nil
        end
      end
    end,
  }
end

return M
