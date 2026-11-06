-- Do not format (ADR-0018): globs, case-sensitive, matched against a file's
-- path from the root, the repo root or else Neovim's working directory. A
-- glob with no `/` matches the file name in any folder.

local M = {}

--- The first glob that matches the path, or nil.
---@param globs string[]
---@param path string the file's path from the root, with `/` between folders
---@return string? glob
function M.match(globs, path)
  local name = vim.fs.basename(path)
  for _, glob in ipairs(globs) do
    local ok, pattern = pcall(vim.glob.to_lpeg, glob)
    if ok and pattern:match(glob:find('/', 1, true) and path or name) then
      return glob
    end
  end
  return nil
end

return M
