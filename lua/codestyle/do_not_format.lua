-- Do not format (ADR-0018): globs, case-sensitive, matched against a file's
-- path from the Project root, Neovim's working directory. A glob with no `/`
-- matches the file name in any folder. For a file outside the Project root,
-- only these file-name globs can match.

local M = {}

--- The first glob that matches the path, or nil.
---@param globs string[]
---@param path string the file's path from the root, with `/` between folders
---@param outside? boolean the file is outside the root: only globs with no `/` can match
---@return string? glob
function M.match(globs, path, outside)
  local name = vim.fs.basename(path)
  for _, glob in ipairs(globs) do
    local folder = glob:find('/', 1, true) ~= nil
    local ok, pattern = pcall(vim.glob.to_lpeg, glob)
    if ok and not (folder and outside) and pattern:match(folder and path or name) then
      return glob
    end
  end
  return nil
end

return M
