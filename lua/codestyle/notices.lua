-- Notices: every warning of the Core goes through `report`, which gives each
-- one only once in the scope that the caller picks.

---@alias codestyle.NoticeScope
---| 'session' once per Neovim session
---| 'buffer' once per buffer and language (the key names both)
---| 'file' once per Code Style file
---| 'filetype' once per filetype
---| 'run' once per format run

---@class codestyle.Notices
---@field report fun(level: integer, scope: codestyle.NoticeScope, key: string, message: string)
---@field begin_run fun() starts a new format run, so the `run` scope is empty again

local M = {}

---@param deps { notify: fun(message: string, level: integer) }
---@return codestyle.Notices
function M.new(deps)
  ---@type table<string, table<string, true>>
  local seen = {}

  ---@type codestyle.Notices
  return {
    report = function(level, scope, key, message)
      seen[scope] = seen[scope] or {}
      if seen[scope][key] then
        return
      end
      seen[scope][key] = true
      deps.notify('codestyle: ' .. message, level)
    end,
    begin_run = function()
      seen.run = nil
    end,
  }
end

return M
