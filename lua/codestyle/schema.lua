-- The Option Schema (ADR-0003, ADR-0018): the six Option types, their
-- validation and defaults, and inheritance from `general`. It does no I/O.

local M = {}

--- An invalid stored value: the Option's default is used instead.
---@class codestyle.Problem
---@field key string the dotted key of the Option, or the stored path that blocks it
---@field message string

---@param value any a decoded JSON value
---@return string
local function show(value)
  if value == vim.NIL then
    return 'null'
  end
  local ok, json = pcall(vim.json.encode, value)
  return ok and json or tostring(value)
end

---@param value any
---@return boolean
local function is_list(value)
  return type(value) == 'table' and vim.islist(value)
end

---@param option codestyle.OptionSpec
---@param value number
---@return string? problem
local function check_range(option, value)
  if (option.min and value < option.min) or (option.max and value > option.max) then
    return ('%s is out of range %s–%s'):format(show(value), option.min or '', option.max or '')
  end
end

---@param option codestyle.OptionSpec
---@param kind 'boolean'|'integer'|'string'
---@param value any
---@return string? problem
local function check_scalar(option, kind, value)
  if kind == 'integer' then
    if type(value) ~= 'number' or value % 1 ~= 0 then
      return 'expected an integer, got ' .. show(value)
    end
    return check_range(option, value)
  end
  if type(value) ~= kind then
    return ('expected a %s, got %s'):format(kind, show(value))
  end
end

--- A stored `order` merged with the default (ADR-0003): an unknown stored
--- member is ignored, and a missing member goes where the default puts it,
--- right after the member that precedes it in the default.
---@param stored string[] distinct strings
---@param default string[]
---@return string[]
local function merge_order(stored, default)
  local known = {}
  for _, member in ipairs(default) do
    known[member] = true
  end
  local merged = vim.tbl_filter(function(member)
    return known[member]
  end, stored)
  for index, member in ipairs(default) do
    if not vim.list_contains(merged, member) then
      local at = 1
      for previous = index - 1, 1, -1 do
        local position = vim.iter(ipairs(merged)):find(function(_, m)
          return m == default[previous]
        end)
        if position then
          at = position + 1
          break
        end
      end
      table.insert(merged, at, member)
    end
  end
  return merged
end

---@param kind 'boolean'|'integer'|'string'
---@return fun(option: codestyle.OptionSpec, value: any): any, string?
local function scalar(kind)
  return function(option, value)
    local problem = check_scalar(option, kind, value)
    if problem then
      return nil, problem
    end
    return value
  end
end

---@type table<codestyle.OptionType, fun(option: codestyle.OptionSpec, value: any): any, string?>
local checkers = {
  boolean = scalar('boolean'),
  integer = scalar('integer'),
  string = scalar('string'),
  choice = function(option, value)
    if type(value) ~= 'string' then
      return nil, 'expected a choice id, got ' .. show(value)
    end
    for _, choice in ipairs(option.choices) do
      if choice.id == value then
        return value
      end
    end
    return nil, 'unknown choice ' .. show(value)
  end,
  list = function(option, value)
    if not is_list(value) then
      return nil, 'expected a list, got ' .. show(value)
    end
    for index, item in ipairs(value) do
      local problem = check_scalar(option, option.item, item)
      if problem then
        return nil, ('item %d: %s'):format(index, problem)
      end
    end
    return value
  end,
  order = function(option, value)
    local seen = {}
    for _, member in ipairs(is_list(value) and value or {}) do
      if type(member) ~= 'string' or seen[member] then
        seen = nil
        break
      end
      seen[member] = true
    end
    if not is_list(value) or not seen then
      return nil, 'expected an order of distinct members, got ' .. show(value)
    end
    return merge_order(value, option.default)
  end,
}

--- Checks a stored value against its Option.
---@param option codestyle.OptionSpec
---@param raw any the stored value, not nil
---@return any value the value to use, nil when the stored value is invalid
---@return string? problem why it is invalid
function M.check(option, raw)
  return checkers[option.type](option, raw)
end

--- The stored value at a dotted key, and the dotted prefix of the key that is
--- stored as something other than an object, if one blocks it.
---@param raw_language table
---@param path string[]
---@return any value
---@return string? blocked
---@return any blocking the stored value at `blocked`
local function stored_at(raw_language, path)
  local node = raw_language
  for index = 1, #path - 1 do
    node = node[path[index]]
    if node == nil then
      return nil
    end
    if type(node) ~= 'table' or is_list(node) then
      return nil, table.concat(path, '.', 1, index), node
    end
  end
  return node[path[#path]]
end

--- The values of a language: each Option's valid stored value, else its
--- default. An Option that inherits a `general` key and has no valid stored
--- value takes the `general` value.
---@param spec { options: codestyle.OptionSpec[] }
---@param raw_language any the stored table of the language, nil when none
---@param general_values? codestyle.Values the resolved `general` values, for Options that inherit
---@return codestyle.Values values nested like the stored keys
---@return codestyle.Problem[] problems
function M.resolve(spec, raw_language, general_values)
  local problems = {} ---@type codestyle.Problem[]
  if raw_language ~= nil and (type(raw_language) ~= 'table' or is_list(raw_language)) then
    table.insert(problems, { key = '', message = 'expected an object, got ' .. show(raw_language) })
    raw_language = nil
  end
  local reported = {} ---@type table<string, true>

  local values = {}
  for _, option in ipairs(spec.options) do
    local path = vim.split(option.key, '.', { plain = true })
    local stored, blocked, blocking = stored_at(raw_language or {}, path)
    local value
    if blocked and not reported[blocked] then
      reported[blocked] = true
      table.insert(problems, { key = blocked, message = 'expected an object, got ' .. show(blocking) })
    elseif stored ~= nil then
      local problem
      value, problem = M.check(option, stored)
      if problem then
        table.insert(problems, { key = option.key, message = problem })
      end
    end
    if value == nil then
      if option.inherit then
        value = vim.tbl_get(general_values or {}, unpack(vim.split(option.inherit, '.', { plain = true })))
      else
        value = vim.deepcopy(option.default)
      end
    end
    local parent = values
    for index = 1, #path - 1 do
      parent[path[index]] = parent[path[index]] or {}
      parent = parent[path[index]]
    end
    parent[path[#path]] = value
  end
  return values, problems
end

return M
