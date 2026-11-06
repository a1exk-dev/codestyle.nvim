-- The Menu's editors of the six Option types (ADR-0003, the #11 resolution):
-- they turn an action on an Option row into a Draft operation. `<Space>` and
-- a right-click toggle a boolean and cycle a choice; `<CR>` and a click edit
-- (`vim.ui.select` for a choice, `vim.ui.input` for an integer or a string, a
-- float for a list or an order); `l`/`h` step; `x` resets. An edit on a
-- dimmed Option is refused with a notice that names the Option it needs.

local float = require('codestyle.menu.float')
local general = require('codestyle.general')
local schema = require('codestyle.schema')
local view = require('codestyle.menu.view')

local M = {}

---@alias codestyle.menu.Action
---| 'toggle' `<Space>` and a right-click
---| 'edit' `<CR>` and a click on the value control
---| 'next' `l`
---| 'prev' `h`
---| 'reset' `x`

--- The Option that an action acts on, in the Draft of the open Menu.
---@class codestyle.menu.Target
---@field draft codestyle.Draft
---@field language string the language id, `general` included
---@field spec { options: codestyle.OptionSpec[] }
---@field option codestyle.OptionSpec

---@class codestyle.menu.Edit
---@field act fun(target: codestyle.menu.Target, action: codestyle.menu.Action)

---@param target codestyle.menu.Target
---@return codestyle.Values
local function values_of(target)
  return target.draft.code_style().values(target.language)
end

---@param spec { options: codestyle.OptionSpec[] }
---@param key string
---@return codestyle.OptionSpec?
local function option_of(spec, key)
  for _, option in ipairs(spec.options) do
    if option.key == key then
      return option
    end
  end
end

--- The next or the previous value for `l`/`h` and for cycling; nil when the
--- type has no such step or an integer would leave its range.
---@param option codestyle.OptionSpec
---@param value any
---@param delta integer 1 or -1
---@return any
local function step_value(option, value, delta)
  if option.type == 'boolean' then
    return not value
  elseif option.type == 'integer' then
    local next_value = value + delta
    if (option.min and next_value < option.min) or (option.max and next_value > option.max) then
      return nil
    end
    return next_value
  elseif option.type == 'choice' then
    local choices = option.choices or {}
    for index, choice in ipairs(choices) do
      if choice.id == value then
        return choices[(index - 1 + delta) % #choices + 1].id
      end
    end
    return choices[1] and choices[1].id
  end
end

---@param deps { notices: codestyle.Notices, on_float_close: fun() }
---@return codestyle.menu.Edit
function M.new(deps)
  ---@param level integer
  ---@param message string
  local function notify(level, message)
    deps.notices.report(level, 'always', 'menu', message)
  end

  --- Refuses an edit of a dimmed Option with a notice that names the Option it needs.
  ---@param target codestyle.menu.Target
  ---@return boolean
  local function refused(target)
    local values = values_of(target)
    local option = target.option
    if schema.active(option, values) then
      return false
    end
    local requires = assert(option.requires)
    local needed = option_of(target.spec, requires.key)
    local name = needed and needed.label or requires.key
    local want ---@type string
    local value = requires.is ~= nil and requires.is or requires.is_not
    if needed and needed.type == 'boolean' then
      want = (value == true) == (requires.is ~= nil) and 'on' or 'off'
    else
      local shown = needed and needed.type == 'choice' and view.choice_label(needed, value) or tostring(value)
      want = (requires.is ~= nil and 'set to "%s"' or 'set to another value than "%s"'):format(shown)
    end
    notify(vim.log.levels.WARN, ('"%s" is inactive: it needs "%s" %s'):format(option.label, name, want))
    return true
  end

  --- A check that the Core adds for `general`: a marker tag in regex mode
  --- must be a valid Vim regex (ADR-0018).
  ---@param target codestyle.menu.Target
  ---@param value any
  ---@return string? problem
  local function core_check(target, value)
    local key = target.option.key
    if target.language == general.id and (key == 'markers.off' or key == 'markers.on') then
      if values_of(target).markers.regex and not pcall(vim.regex, value) then
        return ('"%s" is not a valid Vim regex'):format(value)
      end
    end
  end

  --- Sets the value in the Draft, or tells why it is invalid.
  ---@param target codestyle.menu.Target
  ---@param value any
  ---@return boolean
  local function set(target, value)
    local problem = core_check(target, value)
    local ok = problem == nil
    if ok then
      ok, problem = target.draft.set(target.language, target.option.key, value)
    end
    if not ok then
      notify(vim.log.levels.ERROR, ('%s: %s'):format(target.option.label, problem))
    end
    return ok
  end

  ---@param target codestyle.menu.Target
  ---@param value any
  local function edit_integer(target, value)
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
      set(target, tonumber(input) or input)
    end)
  end

  ---@param target codestyle.menu.Target
  ---@param value any
  local function edit_choice(target, value)
    vim.ui.select(target.option.choices or {}, {
      prompt = target.option.label,
      format_item = function(choice)
        return (choice.id == value and '● ' or '  ') .. choice.label
      end,
    }, function(choice)
      if choice then
        set(target, choice.id)
      end
    end)
  end

  ---@param target codestyle.menu.Target
  ---@param value any
  local function edit_list(target, value)
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
        return set(target, items)
      end,
      on_close = deps.on_float_close,
    })
  end

  ---@param target codestyle.menu.Target
  ---@param value any
  local function edit_order(target, value)
    float.order({
      title = target.option.label,
      lines = vim.deepcopy(value),
      apply = function(members)
        return set(target, members)
      end,
      on_close = deps.on_float_close,
    })
  end

  ---@type table<codestyle.OptionType, fun(target: codestyle.menu.Target, value: any)>
  local editors = {
    boolean = function(target, value)
      set(target, not value)
    end,
    integer = edit_integer,
    choice = edit_choice,
    string = function(target, value)
      vim.ui.input({ prompt = target.option.label .. ': ', default = value }, function(input)
        if input ~= nil then
          set(target, input)
        end
      end)
    end,
    list = edit_list,
    order = edit_order,
  }

  ---@type codestyle.menu.Edit
  return {
    act = function(target, action)
      local option = target.option
      if action == 'reset' then
        target.draft.reset(target.language, option.key)
        return
      end
      local toggles = option.type == 'boolean' or option.type == 'choice'
      if (action == 'toggle' and not toggles) or refused(target) then
        return
      end
      local value = view.value(values_of(target), option.key)
      if action == 'edit' then
        editors[option.type](target, value)
        return
      end
      local next_value = step_value(option, value, action == 'prev' and -1 or 1)
      if next_value ~= nil then
        set(target, next_value)
      end
    end,
  }
end

return M
