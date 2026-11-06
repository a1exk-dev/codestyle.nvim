-- The Menu's Option editing (ADR-0003, the #11 resolution): it turns an
-- action on an Option row into a Draft operation, with the behaviour of each
-- type from `menu.option_types`. `<Space>` and
-- a right-click toggle a boolean and cycle a choice; `<CR>` and a click edit
-- (`vim.ui.select` for a choice, `vim.ui.input` for an integer or a string, a
-- float for a list or an order); `l`/`h` step; `x` resets. An edit on a
-- dimmed Option is refused with a notice that names the Option it needs.

local general = require('codestyle.general')
local option_types = require('codestyle.menu.option_types')
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
    local value = requires.is ~= nil and requires.is or requires.is_not
    local is = requires.is ~= nil
    local want = needed and option_types.of(needed).wanted(needed, value, is)
      or (is and 'set to "%s"' or 'set to another value than "%s"'):format(tostring(value))
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

  ---@type codestyle.menu.Editing
  local editing = { set = set, on_float_close = deps.on_float_close }

  ---@type codestyle.menu.Edit
  return {
    act = function(target, action)
      local option = target.option
      if action == 'reset' then
        target.draft.reset(target.language, option.key)
        return
      end
      local behaviour = option_types.of(option)
      if (action == 'toggle' and not behaviour.toggles) or refused(target) then
        return
      end
      local value = view.value(values_of(target), option.key)
      if action == 'edit' then
        behaviour.edit(target, value, editing)
        return
      end
      local next_value = behaviour.step(option, value, action == 'prev' and -1 or 1)
      if next_value ~= nil then
        set(target, next_value)
      end
    end,
  }
end

return M
