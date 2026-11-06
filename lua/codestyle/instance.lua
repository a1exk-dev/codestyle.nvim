-- The composition root: it wires the Core's modules once, on first use.

local M = {}

---@class codestyle.Instance
---@field format fun(opts?: codestyle.FormatOpts)

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
    local registry = require('codestyle.registry').new()
    local format_api = require('codestyle.format').new({
      notices = notices,
      selector = require('codestyle.selector').new({ registry = registry }),
      store = require('codestyle.store').new({ registry = registry }),
      format_run = require('codestyle.format_run').new({ registry = registry }),
    })
    instance = { format = format_api.format }
  end
  return instance
end

return M
