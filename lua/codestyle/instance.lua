-- The composition root: it wires the Core's modules once, on first use.
-- Wiring loads no Language Plugin: the Registry discovers them on first use.

local M = {}

---@class codestyle.Instance
---@field format fun(opts?: codestyle.FormatOpts)
---@field setup fun(settings?: codestyle.Settings)

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
    local format_api = require('codestyle.format').new({
      notices = notices,
      selector = require('codestyle.selector').new({
        registry = registry,
        settings = settings.get,
        notices = notices,
      }),
      store = require('codestyle.store').new({ registry = registry }),
      format_run = require('codestyle.format_run').new({ registry = registry }),
    })
    instance = { format = format_api.format, setup = settings.set }
  end
  return instance
end

return M
