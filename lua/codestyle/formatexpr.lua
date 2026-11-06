-- `gq` through the Core (ADR-0014, ADR-0015). On `FileType`, a buffer that a
-- Language Plugin claims gets the Core's `formatexpr` unless one is already
-- set, and a buffer that is no longer claimed loses only the Core's own value.

---@class codestyle.Formatexpr
--- The `formatexpr` function: formats `v:lnum` and the `v:count` lines after
--- it. In Insert and Replace mode it returns 1, so Neovim wraps at `textwidth`.
---@field call fun(): integer
---@field on_filetype fun(buf: integer)

local M = {}

--- The `formatexpr` value that the Core sets.
M.value = "v:lua.require'codestyle'.formatexpr()"

---@param deps { format_api: codestyle.FormatApi }
---@return codestyle.Formatexpr
function M.new(deps)
  ---@type codestyle.Formatexpr
  return {
    call = function()
      if vim.fn.mode():find('^[iR]') then
        return 1
      end
      deps.format_api.format({ buf = 0, range = { vim.v.lnum, vim.v.lnum + vim.v.count - 1 } })
      return 0
    end,
    on_filetype = function(buf)
      local current = vim.bo[buf].formatexpr
      if deps.format_api.claimed(buf) then
        if current == '' then
          vim.bo[buf].formatexpr = M.value
        end
      elseif current == M.value then
        vim.bo[buf].formatexpr = ''
      end
    end,
  }
end

return M
