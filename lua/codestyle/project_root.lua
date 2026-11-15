-- The Project root (ADR-0001): Neovim's working directory of the current
-- window, read again at each call, so `:cd`, `:tcd` and `:lcd` switch the
-- project. It is the root of the Project Code Style, of Do not format and of
-- `Project.xml`. `.git` plays no part.

local M = {}

--- The file name of the Project Code Style at the Project root (ADR-0001).
M.project_file = '.codestyle.json'

--- The Project root.
---@return string
function M.get()
  return vim.fs.normalize(vim.fn.getcwd())
end

--- The Project root when the buffer's file is under it, else nil. An unnamed buffer is under it.
---@param buf integer
---@return string?
function M.of(buf)
  local root = M.get()
  local name = vim.api.nvim_buf_get_name(buf)
  if name == '' or vim.fs.relpath(root, name) then
    return root
  end
  return nil
end

return M
