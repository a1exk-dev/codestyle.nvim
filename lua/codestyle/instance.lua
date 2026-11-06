-- The composition root: it wires the Core's modules once, on first use.
-- Wiring loads no Language Plugin: the Registry discovers them on first use.

local M = {}

---@class codestyle.Instance
---@field format fun(opts?: codestyle.FormatOpts)
---@field format_selection fun()
---@field setup fun(settings?: codestyle.Settings) keeps the settings and applies the keys
---@field keys codestyle.Keys
---@field formatexpr codestyle.Formatexpr
---@field conform codestyle.ConformAdapter
---@field health codestyle.Health

---@type codestyle.Instance?
local instance

---@return codestyle.Instance
function M.get()
  if not instance then
    local notices = require('codestyle.notices').new({
      notify = function(message, level)
        vim.notify(message, level)
      end,
    })
    local settings = require('codestyle.settings').new()
    local registry = require('codestyle.registry').new({ notices = notices, api = require('codestyle').api })
    local selector = require('codestyle.selector').new({
      registry = registry,
      settings = settings.get,
      notices = notices,
    })
    local store = require('codestyle.store').new({ registry = registry })
    local format_api = require('codestyle.format').new({
      notices = notices,
      selector = selector,
      store = store,
      format_run = require('codestyle.format_run').new({ registry = registry }),
    })
    local keys = require('codestyle.keys').new({ settings = settings.get })
    local conform = require('codestyle.conform').new({ format_api = format_api })
    instance = {
      format = format_api.format,
      format_selection = format_api.format_selection,
      keys = keys,
      conform = conform,
      health = require('codestyle.health').new({
        selector = selector,
        registry = registry,
        store = store,
        conform = conform,
      }),
      formatexpr = require('codestyle.formatexpr').new({ format_api = format_api }),
      setup = function(new)
        settings.set(new)
        keys.apply()
      end,
    }
  end
  return instance
end

return M
