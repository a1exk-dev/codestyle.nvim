-- How the Menu shows and edits each of the six Option types (ADR-0003, the
-- #11 resolution), in one table, so one type's behaviour lives in one place:
-- its value control, whether `<Space>` toggles it, its `l`/`h` step, how a
-- requirement on it reads, and its `<CR>` editor. The Schema keeps the
-- validation of each type.

local float = require('codestyle.menu.float')

--- What an editor needs from the Menu's Option editors.
---@class codestyle.menu.Editing
---@field set fun(target: codestyle.menu.Target, value: any): boolean sets the value, or tells why it is invalid
---@field on_float_close fun()

---@class codestyle.menu.OptionType
--- The control that shows a value, and its highlight group.
---@field control fun(option: codestyle.OptionSpec, value: any): string, string
---@field checkbox boolean the control comes before the label, as a checkbox
---@field toggles boolean `<Space>` and a right-click act on it
--- The next or the previous value for `l`/`h`; nil when the type has no step or would leave its range.
---@field step fun(option: codestyle.OptionSpec, value: any, delta: integer): any
--- How a requirement on an Option of this type reads: "on", or `set to "<value>"`.
---@field wanted fun(option: codestyle.OptionSpec, value: any, is: boolean): string
--- Opens the editor of `<CR>` and a click.
---@field edit fun(target: codestyle.menu.Target, value: any, editing: codestyle.menu.Editing)

local M = {}

--- The label of a choice id, or the id when the Option has no such choice.
---@param option codestyle.OptionSpec
---@param id any
---@return string
function M.choice_label(option, id)
  for _, choice in ipairs(option.choices or {}) do
    if choice.id == id then
      return choice.label
    end
  end
  return tostring(id)
end

local function no_step() end

--- A requirement that reads as the value it names.
---@param shown string
---@param is boolean
---@return string
local function set_to(shown, is)
  return (is and 'set to "%s"' or 'set to another value than "%s"'):format(shown)
end

---@param option codestyle.OptionSpec
---@param value any
---@param is boolean
---@return string
local function wanted_value(option, value, is)
  return set_to(tostring(value), is)
end

---@type table<codestyle.OptionType, codestyle.menu.OptionType>
M.types = {
  boolean = {
    control = function(_, value)
      return value and '[x]' or '[ ]', 'Special'
    end,
    checkbox = true,
    toggles = true,
    step = function(_, value)
      return not value
    end,
    wanted = function(_, value, is)
      return (value == true) == is and 'on' or 'off'
    end,
    edit = function(target, value, editing)
      editing.set(target, not value)
    end,
  },
  integer = {
    control = function(_, value)
      return ('[ %d ]'):format(value), 'Number'
    end,
    checkbox = false,
    toggles = false,
    step = function(option, value, delta)
      local next_value = value + delta
      if (option.min and next_value < option.min) or (option.max and next_value > option.max) then
        return nil
      end
      return next_value
    end,
    wanted = wanted_value,
    edit = function(target, value, editing)
      local option = target.option
      local hint = option.inherit and ' (empty: inherit General)' or ''
      vim.ui.input({
        prompt = ('%s [%s–%s]%s: '):format(option.label, option.min or '', option.max or '', hint),
        default = tostring(value),
      }, function(input)
        if input == nil then
          return
        end
        input = vim.trim(input)
        if input == '' then
          if option.inherit then
            target.draft.reset(target.language, option.key)
          end
          return
        end
        editing.set(target, tonumber(input) or input)
      end)
    end,
  },
  choice = {
    control = function(option, value)
      return ('‹%s›'):format(M.choice_label(option, value)), 'Constant'
    end,
    checkbox = false,
    toggles = true,
    step = function(option, value, delta)
      local choices = option.choices or {}
      for index, choice in ipairs(choices) do
        if choice.id == value then
          return choices[(index - 1 + delta) % #choices + 1].id
        end
      end
      return choices[1] and choices[1].id
    end,
    wanted = function(option, value, is)
      return set_to(M.choice_label(option, value), is)
    end,
    edit = function(target, value, editing)
      vim.ui.select(target.option.choices or {}, {
        prompt = target.option.label,
        format_item = function(choice)
          return (choice.id == value and '● ' or '  ') .. choice.label
        end,
      }, function(choice)
        if choice then
          editing.set(target, choice.id)
        end
      end)
    end,
  },
  string = {
    control = function(_, value)
      return ('"%s"'):format(value), 'String'
    end,
    checkbox = false,
    toggles = false,
    step = no_step,
    wanted = wanted_value,
    edit = function(target, value, editing)
      vim.ui.input({ prompt = target.option.label .. ': ', default = value }, function(input)
        if input ~= nil then
          editing.set(target, input)
        end
      end)
    end,
  },
  list = {
    control = function(_, value)
      return ('[%s]'):format(table.concat(vim.tbl_map(tostring, value), ', ')), 'Constant'
    end,
    checkbox = false,
    toggles = false,
    step = no_step,
    wanted = wanted_value,
    edit = function(target, value, editing)
      local option = target.option
      float.list({
        title = option.label,
        lines = vim.tbl_map(tostring, value),
        apply = function(items)
          if option.item == 'integer' then
            items = vim.tbl_map(function(item)
              return tonumber(item) or item
            end, items)
          end
          return editing.set(target, items)
        end,
        on_close = editing.on_float_close,
      })
    end,
  },
  order = {
    control = function(_, value)
      return table.concat(value, ' › '), 'Constant'
    end,
    checkbox = false,
    toggles = false,
    step = no_step,
    wanted = wanted_value,
    edit = function(target, value, editing)
      float.order({
        title = target.option.label,
        lines = vim.deepcopy(value),
        apply = function(items)
          return editing.set(target, items)
        end,
        on_close = editing.on_float_close,
      })
    end,
  },
}

--- The behaviour of an Option's type.
---@param option codestyle.OptionSpec
---@return codestyle.menu.OptionType
function M.of(option)
  return M.types[option.type]
end

return M
