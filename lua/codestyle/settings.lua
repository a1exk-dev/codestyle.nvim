-- Settings (#50 module 17): the user's choices from `setup{}`, kept in one
-- table. Other modules read them through the getter they are given, and never
-- read globals.

---@class codestyle.Settings
--- Filetype → language id, or `false` to turn codestyle off for the filetype (ADR-0015).
---@field filetypes? table<string, string|false>
--- The user's own Presets, shown after the plugin's in the "Set from…" list of `language` (ADR-0006).
---@field presets? codestyle.UserPreset[]

---@class codestyle.UserPreset: codestyle.Preset
---@field language string the language id whose "Set from…" list shows the Preset, `general` included

---@class codestyle.SettingsStore
---@field get fun(): codestyle.Settings
---@field set fun(settings?: codestyle.Settings) replaces the settings

local M = {}

---@return codestyle.SettingsStore
function M.new()
  ---@type codestyle.Settings
  local settings = {}

  ---@type codestyle.SettingsStore
  return {
    get = function()
      return settings
    end,
    set = function(new)
      settings = vim.deepcopy(new or {})
    end,
  }
end

return M
