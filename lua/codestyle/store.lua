-- The Code Style Store (ADR-0001): it finds and reads the Global and the
-- Project Code Style files, and applies the plugins' migrations on read.
--
-- A broken file (not valid JSON, or an unknown `version`) is refused as a
-- whole: no buffer of that scope is formatted, because falling back to the
-- defaults would rewrite the whole file (#50 New decisions).

local arrangement = require('codestyle.arrangement')
local code_style = require('codestyle.code_style')
local general = require('codestyle.general')
local json = require('codestyle.json')
local migrations = require('codestyle.migrations')
local repo = require('codestyle.repo')
local schema = require('codestyle.schema')
local tree = require('codestyle.tree')

---@alias codestyle.Scope 'global'|'project'

--- Why a Code Style file cannot be used at all.
---@class codestyle.BrokenFile
---@field path string
---@field line integer 1-based
---@field message string

---@class codestyle.Store
---@field path fun(scope: codestyle.Scope, root?: string): string the file of the scope
---@field load fun(scope: codestyle.Scope, root?: string): codestyle.CodeStyle?, codestyle.BrokenFile? `root` is the repo root of the `project` scope
---@field for_buffer fun(buf: integer): codestyle.CodeStyle?, codestyle.Scope the saved Code Style that formats the buffer; nil, with one ERROR, when its file is broken
---@field save fun(scope: codestyle.Scope, root: string?, style: codestyle.CodeStyle): boolean, string? writes the file; false and why when it cannot

local M = {}

--- The `version` of the file format that this Core reads and writes (ADR-0001).
local VERSION = 1

---@param text string
---@param offset integer a 1-based byte offset
---@return integer line
local function line_at(text, offset)
  local _, breaks = text:sub(1, offset - 1):gsub('\n', '')
  return breaks + 1
end

--- The line of a key of the top-level JSON object, or 1 when it is absent.
---@param text string valid JSON
---@param key string
---@return integer
local function top_level_key_line(text, key)
  local depth, index = 0, 1
  while index <= #text do
    local char = text:sub(index, index)
    if char == '"' then
      local close = index + 1
      while text:sub(close, close) ~= '"' do
        close = close + (text:sub(close, close) == '\\' and 2 or 1)
      end
      if depth == 1 and text:sub(index + 1, close - 1) == key and text:find('^%s*:', close + 1) then
        return line_at(text, index)
      end
      index = close
    elseif char == '{' or char == '[' then
      depth = depth + 1
    elseif char == '}' or char == ']' then
      depth = depth - 1
    end
    index = index + 1
  end
  return 1
end

--- The content of a Code Style file; a missing file is an empty Code Style.
---@param path string
---@return codestyle.StoredFile?
---@return codestyle.BrokenFile?
local function read(path)
  local file = io.open(path, 'r')
  if not file then
    return { version = VERSION, languages = {} }
  end
  local text = file:read('*a')
  file:close()

  local ok, decoded = pcall(vim.json.decode, text)
  if not ok then
    local message = tostring(decoded):gsub('^.-:%d+: ', '')
    local offset = tonumber(message:match(' at character (%d+)$')) or 1
    message = message:gsub(' at character %d+$', '')
    return nil, { path = path, line = line_at(text, offset), message = ('not valid JSON (%s)'):format(message) }
  end
  if type(decoded) ~= 'table' or vim.islist(decoded) then
    return nil, { path = path, line = 1, message = 'not a Code Style file, the top level is not an object' }
  end
  if decoded.version ~= VERSION then
    return nil,
      {
        path = path,
        line = top_level_key_line(text, 'version'),
        message = ('unknown version %s, this Core reads version %d'):format(vim.json.encode(decoded.version), VERSION),
      }
  end
  if decoded.languages ~= nil and (type(decoded.languages) ~= 'table' or vim.islist(decoded.languages)) then
    return nil, { path = path, line = top_level_key_line(text, 'languages'), message = '"languages" is not an object' }
  end
  return decoded
end

---@param scope codestyle.Scope
---@param root? string
---@return string
local function path_of(scope, root)
  if scope == 'project' then
    return vim.fs.joinpath(assert(root, 'the project scope needs a repo root'), repo.project_file)
  end
  return vim.fs.joinpath(vim.fn.stdpath('config') --[[@as string]], 'codestyle.json')
end

--- The file content to write (ADR-0001, ADR-0003): a valid value that equals
--- its Option's default is left out, and so is each object that this leaves
--- empty. Invalid values, unknown keys and unknown languages stay as they
--- are. The reserved `arrangement` key is left out only when it is valid and
--- the same as the default (ADR-0011). A value of an Option that inherits is
--- kept, because it was set.
---@param raw codestyle.StoredFile
---@param registry codestyle.Registry
---@return table
local function minimal(raw, registry)
  local content = vim.deepcopy(raw)
  local languages = content.languages or {}
  for _, id in ipairs({ general.id, unpack(code_style.used_languages(registry)) }) do
    local stored = languages[id]
    if tree.is_object(stored) then
      local spec = id == general.id and general or registry.get(id) --[[@as codestyle.Spec]]
      for _, option in ipairs(spec.options) do
        local path = tree.path(option.key)
        local value = tree.get(stored, path)
        if value ~= nil and not option.inherit and vim.deep_equal(schema.check(option, value), option.default) then
          tree.remove(stored, path)
        end
      end
      if spec.arrangement and stored.arrangement ~= nil then
        local valid, problem = arrangement.validate(spec.arrangement, stored.arrangement)
        if not problem and vim.deep_equal(valid, arrangement.validate(spec.arrangement, nil)) then
          stored.arrangement = nil
        end
      end
      if next(stored) == nil then
        languages[id] = nil
      end
    end
  end
  content.version = VERSION
  content.languages = next(languages) ~= nil and languages or nil
  return content
end

---@param deps { notices: codestyle.Notices, registry: codestyle.Registry }
---@return codestyle.Store
function M.new(deps)
  local function load(scope, root)
    local raw, broken = read(path_of(scope, root))
    if not raw then
      return nil, broken
    end
    raw.languages = raw.languages or {}
    for _, id in ipairs(code_style.used_languages(deps.registry)) do
      local spec = deps.registry.get(id) --[[@as codestyle.Spec]]
      raw.languages[id] = migrations.apply(spec.migrations or {}, raw.languages[id])
    end
    return code_style.new(raw, deps.registry)
  end

  --- One WARN per file that lists its invalid values (ADR-0003). It comes
  --- again only when the list changes.
  ---@param path string
  ---@param style codestyle.CodeStyle
  local function warn_problems(path, style)
    local problems = vim.tbl_map(function(problem)
      local key = problem.key == '' and problem.language or problem.language .. '.' .. problem.key
      return key .. ': ' .. problem.message
    end, style.problems())
    if #problems > 0 then
      local message = ('%s: invalid values, their defaults are used: %s'):format(path, table.concat(problems, '; '))
      deps.notices.report(vim.log.levels.WARN, 'file', message, message)
    end
  end

  ---@type codestyle.Store
  return {
    path = path_of,
    load = load,
    save = function(scope, root, style)
      local path = path_of(scope, root)
      local _, broken = read(path)
      if broken then
        return false, ('%s:%d: %s; fix or delete the file first'):format(broken.path, broken.line, broken.message)
      end
      vim.fn.mkdir(vim.fs.dirname(path), 'p')
      local file, message = io.open(path, 'w')
      if not file then
        return false, tostring(message)
      end
      file:write(json.encode(minimal(style.raw(), deps.registry)))
      file:close()
      return true
    end,
    for_buffer = function(buf)
      local root = repo.root(buf)
      local scope = (root and vim.uv.fs_stat(path_of('project', root))) and 'project' or 'global'
      local style, broken = load(scope, root)
      local path = path_of(scope, root)
      if style then
        warn_problems(path, style)
      else
        broken = broken --[[@as codestyle.BrokenFile]]
        deps.notices.report(
          vim.log.levels.ERROR,
          'run',
          broken.path,
          ('%s:%d: %s; nothing is formatted with this Code Style'):format(broken.path, broken.line, broken.message)
        )
      end
      return style, scope
    end,
  }
end

return M
