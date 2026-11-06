-- The shared test helper of the Core (#50 Testing Decisions, ADR-0017).
--
-- Every test runs the Core in a child Neovim. `child.setup()` gives each case
-- a fresh child whose XDG folders and repo root are temporary folders, with
-- the fake Language Plugins of `tests/fixtures/` on the runtimepath. Tests then
-- write a Code Style file, open a buffer, format it through a public entry
-- point and read the lines and notices back. Nothing here reaches into the
-- Core's modules.

local Helpers = {}

local root = vim.fs.normalize(vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':p:h:h'))

---@class codestyle.test.Notice
---@field message string
---@field level integer a `vim.log.levels` value

---@class codestyle.test.Paths
---@field root string the temporary folder of the case
---@field config string `stdpath('config')` of the child
---@field repo string a repo root (it has `.git`)

---@class codestyle.test.Child: MiniTest.child
---@field paths codestyle.test.Paths
local Child = {}

--- Starts a fresh child Neovim for one case.
--- `opts.plugins`: fake plugins (folder names in `tests/fixtures/`), default `{ 'codestyle-lua.nvim' }`.
--- `opts.cmd`: Ex commands that run before the init file and the plugins load, like a user's
--- early config.
---@param opts? { plugins?: string[], cmd?: string[] }
function Child:setup(opts)
  opts = opts or {}
  local tmp = vim.fn.tempname()
  self.paths = {
    root = tmp,
    config = tmp .. '/xdg/config/nvim',
    repo = tmp .. '/repo',
  }
  for _, dir in ipairs({ 'config', 'data', 'state', 'cache' }) do
    vim.fn.mkdir(tmp .. '/xdg/' .. dir, 'p')
    vim.env['XDG_' .. dir:upper() .. '_HOME'] = tmp .. '/xdg/' .. dir
  end
  vim.fn.mkdir(self.paths.config, 'p')
  vim.fn.mkdir(self.paths.repo .. '/.git', 'p')

  local args = { '-u', root .. '/tests/minimal_init.lua' }
  for _, cmd in ipairs(opts.cmd or {}) do
    vim.list_extend(args, { '--cmd', cmd })
  end
  self.restart(args)
  for _, plugin in ipairs(opts.plugins or { 'codestyle-lua.nvim' }) do
    self.lua('vim.opt.runtimepath:append(...)', { root .. '/tests/fixtures/' .. plugin })
  end
  self.lua([[
    _G.test_notices = {}
    vim.notify = function(message, level)
      table.insert(_G.test_notices, { message = message, level = level or vim.log.levels.INFO })
    end
  ]])
end

--- Stops the child and deletes the case's temporary folder.
function Child:teardown()
  self.stop()
  if self.paths then
    vim.fn.delete(self.paths.root, 'rf')
  end
end

--- Writes a file, creating its folders.
---@param path string
---@param content string|table a table is written as JSON
function Child:write_file(path, content)
  if type(content) == 'table' then
    content = vim.json.encode(content)
  end
  vim.fn.mkdir(vim.fs.dirname(path), 'p')
  local file = assert(io.open(path, 'w'))
  file:write(content)
  file:close()
end

--- Writes the Global Code Style file, `stdpath('config')/codestyle.json`.
---@param content string|table a table is written as JSON
function Child:write_global(content)
  self:write_file(self.paths.config .. '/codestyle.json', content)
end

--- Opens a new buffer with these lines and this filetype and makes it current.
--- Setting the lines is not an undo step, so one `u` after a format restores them.
---@param opts { lines: string[], filetype?: string, name?: string } `name` is the buffer's file name (the file itself is not written)
---@return integer buf
function Child:open_buffer(opts)
  return self.lua(
    [[
      local lines, filetype, name = ...
      local buf = vim.api.nvim_create_buf(true, false)
      if name ~= '' then
        vim.api.nvim_buf_set_name(buf, name)
      end
      vim.api.nvim_set_current_buf(buf)
      local undolevels = vim.bo[buf].undolevels
      vim.bo[buf].undolevels = -1
      vim.api.nvim_buf_set_lines(buf, 0, -1, true, lines)
      vim.bo[buf].undolevels = undolevels
      vim.bo[buf].filetype = filetype
      return buf
    ]],
    { opts.lines, opts.filetype or '', opts.name or '' }
  )
end

--- Calls the public `require('codestyle').format(opts)`.
---@param opts? table
function Child:format(opts)
  return self.lua('return require("codestyle").format(...)', { opts or {} })
end

---@param buf integer
---@return string[]
function Child:lines(buf)
  return self.api.nvim_buf_get_lines(buf, 0, -1, true)
end

--- The `ctx.values` that the fake `lua` formatter got in the last format run.
---@return table
function Child:plugin_values()
  return self.lua_get('_G.codestyle_test_values')
end

--- Every `vim.notify` call of the child since `setup()`.
---@return codestyle.test.Notice[]
function Child:notices()
  return self.lua_get('_G.test_notices')
end

--- A child Neovim with the helper's methods. Call `child:setup()` before each
--- case and `child:teardown()` after it.
---@return codestyle.test.Child
function Helpers.new_child()
  local child = MiniTest.new_child_neovim()
  for name, method in pairs(Child) do
    child[name] = method
  end
  ---@cast child codestyle.test.Child
  return child
end

Helpers.levels = vim.log.levels

return Helpers
