-- The repo root (#50 New decisions): the nearest folder above a buffer that
-- has `.codestyle.json`, else the nearest one that has `.git`. It is the root
-- of the Project Code Style, of Do not format and of `Project.xml`.

local M = {}

--- The file name of the Project Code Style at the repo root (ADR-0001).
M.project_file = '.codestyle.json'

--- The repo root of a buffer. An unnamed buffer searches from the working directory.
---@param buf integer
---@return string? root nil outside a repo
function M.root(buf)
  return vim.fs.root(buf, M.project_file) or vim.fs.root(buf, '.git')
end

return M
