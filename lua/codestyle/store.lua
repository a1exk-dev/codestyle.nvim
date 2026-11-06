-- The Code Style Store (ADR-0001): it finds and reads the Code Style files.
-- Today it reads the Global file only.

local code_style = require('codestyle.code_style')

---@alias codestyle.Scope 'global'

---@class codestyle.Store
---@field load fun(scope: codestyle.Scope): codestyle.CodeStyle
---@field for_buffer fun(buf: integer): codestyle.CodeStyle, codestyle.Scope the saved Code Style that formats the buffer

local M = {}

---@param path string
---@return codestyle.StoredFile
local function read(path)
  local file = io.open(path, 'r')
  if not file then
    return { version = 1, languages = {} }
  end
  local text = file:read('*a')
  file:close()
  return vim.json.decode(text)
end

---@param deps { registry: codestyle.Registry }
---@return codestyle.Store
function M.new(deps)
  local function load(scope)
    assert(scope == 'global')
    return code_style.new(read(vim.fs.joinpath(vim.fn.stdpath('config'), 'codestyle.json')), deps.registry)
  end

  ---@type codestyle.Store
  return {
    load = load,
    for_buffer = function(_)
      return load('global'), 'global'
    end,
  }
end

return M
