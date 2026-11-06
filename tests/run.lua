-- The one headless command that runs the Core's tests (ADR-0017):
--
--   nvim --headless -l tests/run.lua [file ...]
--
-- It clones the pinned dependencies of `tests/deps.lua` into `.tests/`,
-- then runs mini.test over `tests/` (or over the given files).
-- The exit status is non-zero when a case fails.
--
--   nvim --headless -l tests/run.lua --deps
--
-- only clones the dependencies, for example for `lua-language-server --check`.

local root = vim.fs.normalize(vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':p:h:h'))

---@param cmd string[]
local function git(cmd)
  local result = vim.system(vim.list_extend({ 'git' }, cmd), { text = true }):wait()
  if result.code ~= 0 then
    io.stderr:write(('git %s failed:\n%s\n'):format(table.concat(cmd, ' '), result.stderr))
    os.exit(1)
  end
  return vim.trim(result.stdout)
end

for _, dep in ipairs(dofile(root .. '/tests/deps.lua')) do
  local path = root .. '/.tests/' .. dep.name
  if not vim.uv.fs_stat(path) then
    git({ 'clone', '--quiet', '--filter=blob:none', dep.url, path })
  end
  if git({ '-C', path, 'rev-parse', 'HEAD' }) ~= dep.commit then
    git({ '-C', path, 'fetch', '--quiet', 'origin', dep.commit })
    git({ '-C', path, 'checkout', '--quiet', '--detach', dep.commit })
  end
end

if _G.arg[1] == '--deps' then
  return
end

vim.cmd.cd(root)
dofile(root .. '/tests/minimal_init.lua')

local files = #_G.arg > 0 and _G.arg or nil
require('mini.test').setup()
MiniTest.run({
  collect = files and {
    find_files = function()
      return files
    end,
  } or nil,
})
