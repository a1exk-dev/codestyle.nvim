-- The Draft (ADR-0006, ADR-0012): an editable copy of one scope's Code Style.
-- Every operation that changes it is one undo step; save and discard clear
-- the history. Observers, such as the Preview and the Menu, subscribe to its
-- changes; the Draft knows nothing about them.
--
-- The Draft edits the stored content, not the resolved values, so whatever an
-- operation does not touch stays as it was read: an invalid value until its
-- Option is set or reset, unknown keys and languages, and the reserved
-- `arrangement` key until the Arrangement is set or reset (ADR-0003, ADR-0012).

local arrangement = require('codestyle.arrangement')
local code_style = require('codestyle.code_style')
local general = require('codestyle.general')
local schema = require('codestyle.schema')
local tree = require('codestyle.tree')

--- Values to merge into the Draft: language id → dotted Option key → value.
---@alias codestyle.Patch table<string, table<string, any>>

--- The stored values of a language that has no installed Language Plugin.
---@class codestyle.KeptLanguage
---@field id string
---@field count integer the number of stored values

---@class codestyle.Draft
---@field scope codestyle.Scope
---@field root? string the repo root of the `project` scope
---@field set fun(id: string, key: string, value: any): boolean, string? false and the problem when the value is invalid; the Draft is then unchanged
---@field reset fun(id: string, key: string) back to the default: the stored value is removed
---@field set_arrangement fun(id: string, value: any) stores the language's Arrangement
---@field reset_arrangement fun(id: string) back to the default Arrangement
---@field apply fun(patch: codestyle.Patch) merges checked values, such as a Preset's, as one step
---@field undo fun(): boolean false when there is nothing to undo
---@field redo fun(): boolean false when there is nothing to redo
---@field changed fun(id: string): integer the number of the language's values that differ from the default, the Arrangement counting as one
---@field arrangement_changed fun(id: string): boolean true when the stored Arrangement is valid and differs from the default
---@field changed_keys fun(id: string): table<string, true> the keys of the language's Options whose stored value is valid and differs from the default; an inherit Option counts when it is set
---@field modified fun(): boolean true when the Draft differs from the saved Code Style
---@field kept_languages fun(): codestyle.KeptLanguage[] sorted by id
---@field code_style fun(): codestyle.CodeStyle the Draft as a Code Style, for the Preview
---@field save fun(): boolean, string? writes the file through the Store; false and why when it cannot
---@field discard fun() back to the saved Code Style
---@field subscribe fun(observer: fun()): fun() calls `observer` after each change; returns the unsubscribe function

local M = {}

--- The reserved key of a language's Arrangement (ADR-0011).
local ARRANGEMENT = 'arrangement'

---@param deps { store: codestyle.Store, registry: codestyle.Registry, scope: codestyle.Scope, root?: string }
---@return codestyle.Draft?
---@return codestyle.BrokenFile? broken when the scope's file is broken; the Draft does not open
function M.new(deps)
  local registry = deps.registry
  local saved, broken = deps.store.load(deps.scope, deps.root)
  if not saved then
    return nil, broken
  end

  ---@type codestyle.StoredFile[]
  local steps = { vim.deepcopy(saved.raw()) }
  local index = 1
  ---@type table<fun(), true>
  local observers = {}
  ---@type codestyle.CodeStyle?
  local current_style

  local function current()
    return steps[index]
  end

  local function changed_now()
    current_style = nil
    for observer in pairs(observers) do
      observer()
    end
  end

  --- Makes one undo step from a change of a copy of the current content. A
  --- change that changes nothing makes no step.
  ---@param change fun(languages: table<string, any>)
  local function step(change)
    local next_content = vim.deepcopy(current())
    next_content.languages = next_content.languages or {}
    change(next_content.languages)
    if vim.deep_equal(next_content, current()) then
      return
    end
    for later = #steps, index + 1, -1 do
      steps[later] = nil
    end
    table.insert(steps, next_content)
    index = #steps
    changed_now()
  end

  ---@param id string
  ---@return { options: codestyle.OptionSpec[] }
  local function spec_of(id)
    if id == general.id then
      return general
    end
    assert(vim.list_contains(code_style.used_languages(registry), id), 'not an installed language: ' .. id)
    return registry.get(id) --[[@as codestyle.Spec]]
  end

  ---@param id string
  ---@param key string
  ---@return codestyle.OptionSpec
  local function option_of(id, key)
    for _, option in ipairs(spec_of(id).options) do
      if option.key == key then
        return option
      end
    end
    error(('%s has no Option %s'):format(id, key))
  end

  --- The language's stored table, an empty object when it is none.
  ---@param languages table<string, any>
  ---@param id string
  ---@return table
  local function language(languages, id)
    if not tree.is_object(languages[id]) then
      languages[id] = {}
    end
    return languages[id]
  end

  ---@param languages table<string, any>
  ---@param id string
  local function drop_if_empty(languages, id)
    if type(languages[id]) == 'table' and next(languages[id]) == nil then
      languages[id] = nil
    end
  end

  ---@param languages table<string, any>
  ---@param id string
  ---@param path string[]
  local function remove(languages, id, path)
    if tree.is_object(languages[id]) then
      tree.remove(languages[id], path)
      drop_if_empty(languages, id)
    end
  end

  ---@param id string
  ---@return table<string, true>
  local function changed_keys(id)
    local stored = (current().languages or {})[id]
    local keys = {} ---@type table<string, true>
    for _, option in ipairs(spec_of(id).options) do
      local raw = tree.get(stored, tree.path(option.key))
      local value = raw ~= nil and schema.check(option, raw)
      if raw ~= nil and value ~= nil and (option.inherit or not vim.deep_equal(value, option.default)) then
        keys[option.key] = true
      end
    end
    return keys
  end

  ---@param id string
  ---@return boolean
  local function arrangement_changed(id)
    local spec = id ~= general.id and spec_of(id) --[[@as codestyle.Spec]]
    local stored = tree.get((current().languages or {})[id], { ARRANGEMENT })
    if not spec or not spec.arrangement or stored == nil then
      return false
    end
    local valid, problem = arrangement.validate(spec.arrangement, stored)
    return not problem and not vim.deep_equal(valid, arrangement.validate(spec.arrangement, nil))
  end

  local function clear_history()
    steps = { current() }
    index = 1
  end

  ---@type codestyle.Draft
  return {
    scope = deps.scope,
    root = deps.root,
    set = function(id, key, value)
      local _, problem = schema.check(option_of(id, key), value)
      if problem then
        return false, problem
      end
      step(function(languages)
        tree.set(language(languages, id), tree.path(key), vim.deepcopy(value))
      end)
      return true
    end,
    reset = function(id, key)
      option_of(id, key)
      step(function(languages)
        remove(languages, id, tree.path(key))
      end)
    end,
    set_arrangement = function(id, value)
      spec_of(id)
      step(function(languages)
        language(languages, id)[ARRANGEMENT] = vim.deepcopy(value)
      end)
    end,
    reset_arrangement = function(id)
      spec_of(id)
      step(function(languages)
        remove(languages, id, { ARRANGEMENT })
      end)
    end,
    apply = function(patch)
      step(function(languages)
        for id, values in pairs(patch) do
          for key, value in pairs(values) do
            tree.set(language(languages, id), tree.path(key), vim.deepcopy(value))
          end
        end
      end)
    end,
    undo = function()
      if index == 1 then
        return false
      end
      index = index - 1
      changed_now()
      return true
    end,
    redo = function()
      if index == #steps then
        return false
      end
      index = index + 1
      changed_now()
      return true
    end,
    changed_keys = changed_keys,
    arrangement_changed = arrangement_changed,
    changed = function(id)
      local count = vim.tbl_count(changed_keys(id))
      if arrangement_changed(id) then
        count = count + 1
      end
      return count
    end,
    modified = function()
      return not vim.deep_equal(current(), steps[1])
    end,
    kept_languages = function()
      local used = { [general.id] = true }
      for _, id in ipairs(code_style.used_languages(registry)) do
        used[id] = true
      end
      local kept = {} ---@type codestyle.KeptLanguage[]
      for id, stored in pairs(current().languages or {}) do
        if not used[id] then
          local count = 0
          local function count_leaves(node)
            if tree.is_object(node) then
              for _, child in pairs(node) do
                count_leaves(child)
              end
            else
              count = count + 1
            end
          end
          count_leaves(stored)
          table.insert(kept, { id = id, count = count })
        end
      end
      table.sort(kept, function(a, b)
        return a.id < b.id
      end)
      return kept
    end,
    code_style = function()
      current_style = current_style or code_style.new(vim.deepcopy(current()), registry)
      return current_style
    end,
    save = function()
      local ok, problem = deps.store.save(deps.scope, deps.root, code_style.new(current(), registry))
      if ok then
        clear_history()
      end
      return ok, problem
    end,
    discard = function()
      local was = current()
      index = 1
      clear_history()
      if not vim.deep_equal(was, current()) then
        changed_now()
      end
    end,
    subscribe = function(observer)
      observers[observer] = true
      return function()
        observers[observer] = nil
      end
    end,
  }
end

return M
