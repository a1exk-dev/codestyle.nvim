-- Startup file of the test runner and of every child Neovim.
-- It puts the Core and the pinned test dependencies on the runtimepath.
-- It installs nothing: `tests/run.lua` clones the dependencies first.

local root = vim.fs.normalize(vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':p:h:h'))

vim.opt.runtimepath:prepend(root)
for _, dep in ipairs(dofile(root .. '/tests/deps.lua')) do
  vim.opt.runtimepath:append(root .. '/.tests/' .. dep.name)
end

vim.o.swapfile = false
vim.o.shadafile = 'NONE'
