-- Presets (ADR-0006): the "Set from…" list of a language, from the plugins'
-- specs and the user's `setup{ presets }`, and the patch that a Preset makes
-- of the values that the Draft can take. A Code Style never records which
-- Preset was applied.

local code_style = require('codestyle.code_style')
local general = require('codestyle.general')
local schema = require('codestyle.schema')
local tree = require('codestyle.tree')

--- A Preset in a "Set from…" list.
---@class codestyle.PresetItem: codestyle.Preset
---@field label string the name, with " (user)" for the user's own Presets
---@field language string the language whose list shows it
---@field user boolean

--- A value of a Preset that was not applied.
---@class codestyle.SkippedValue
---@field key string the language id and the dotted key, such as `lua.indent.size`
---@field reason string

---@class codestyle.Presets
---@field list fun(id: string): codestyle.PresetItem[] the plugin's Presets in the spec's order, then the user's
---@field to_patch fun(preset: codestyle.Preset): codestyle.Patch, codestyle.SkippedValue[]
---@field apply fun(draft: codestyle.Draft, preset: codestyle.PresetItem): codestyle.SkippedValue[] one Draft step, and one notice that lists what was skipped

local M = {}

---@param deps { registry: codestyle.Registry, setup: (fun(): codestyle.Setup), notices: codestyle.Notices }
---@return codestyle.Presets
function M.new(deps)
  local registry = deps.registry

  ---@param id string
  ---@return { options: codestyle.OptionSpec[] }?
  local function installed(id)
    if id == general.id then
      return general
    end
    return vim.list_contains(code_style.used_languages(registry), id) and registry.get(id) or nil
  end

  --- The checked values of one language of a Preset, keyed by dotted Option key.
  ---@param id string
  ---@param spec { options: codestyle.OptionSpec[] }
  ---@param values any
  ---@param skip fun(key: string, reason: string)
  ---@return table<string, any>
  local function language_patch(id, spec, values, skip)
    local options = {} ---@type table<string, codestyle.OptionSpec>
    for _, option in ipairs(spec.options) do
      options[option.key] = option
    end
    local patch = {}
    ---@param node table
    ---@param prefix string
    local function walk(node, prefix)
      for part, value in pairs(node) do
        local key = prefix == '' and part or prefix .. '.' .. part
        if key == 'arrangement' and id ~= general.id then
          skip(key, 'Presets never set Arrangement')
        elseif options[key] then
          local _, problem = schema.check(options[key], value)
          if problem then
            skip(key, problem)
          else
            patch[key] = value
          end
        elseif tree.is_object(value) and next(value) ~= nil then
          walk(value, key)
        else
          skip(key, 'no such Option')
        end
      end
    end
    if tree.is_object(values) then
      walk(values, '')
    else
      skip('', 'expected an object')
    end
    return patch
  end

  ---@param preset codestyle.Preset
  ---@return codestyle.Patch
  ---@return codestyle.SkippedValue[]
  local function to_patch(preset)
    local patch = {} ---@type codestyle.Patch
    local skipped = {} ---@type codestyle.SkippedValue[]
    for id, values in pairs(preset.values or {}) do
      local function skip(key, reason)
        table.insert(skipped, { key = key == '' and id or id .. '.' .. key, reason = reason })
      end
      local spec = installed(id)
      if spec then
        patch[id] = language_patch(id, spec, values, skip)
      else
        skip('', 'Language Plugin not installed')
      end
    end
    table.sort(skipped, function(a, b)
      return a.key < b.key
    end)
    return patch, skipped
  end

  ---@type codestyle.Presets
  return {
    list = function(id)
      local items = {} ---@type codestyle.PresetItem[]
      local spec = id ~= general.id and registry.get(id) or nil
      for _, preset in ipairs(spec and spec.presets or {}) do
        table.insert(
          items,
          { name = preset.name, label = preset.name, language = id, values = preset.values, user = false }
        )
      end
      for _, preset in ipairs(deps.setup().presets or {}) do
        if preset.language == id then
          table.insert(items, {
            name = preset.name,
            label = preset.name .. ' (user)',
            language = id,
            values = preset.values,
            user = true,
          })
        end
      end
      return items
    end,
    to_patch = to_patch,
    apply = function(draft, preset)
      local patch, skipped = to_patch(preset)
      draft.apply(patch)
      if #skipped > 0 then
        local listed = vim.tbl_map(function(value)
          return value.key .. ': ' .. value.reason
        end, skipped)
        deps.notices.report(
          vim.log.levels.WARN,
          'always',
          preset.label,
          ('Preset "%s" skipped %d values: %s'):format(preset.label, #skipped, table.concat(listed, '; '))
        )
      end
      return skipped
    end,
  }
end

return M
