-- Setup (#50 module 17): the user's choices from `setup{}`, kept in one
-- table. Other modules read them through the getter they are given, and never
-- read globals.

---@class codestyle.Setup
--- Filetype → language id, or `false` to turn codestyle off for the filetype (ADR-0015).
---@field filetypes? table<string, string|false>
--- `false` leaves the default key `<leader>cf` unmapped (ADR-0014). Default true.
---@field keys? boolean
--- The user's own Presets, shown after the plugin's in the "Set from…" list of `language` (ADR-0006).
---@field presets? codestyle.UserPreset[]

---@class codestyle.UserPreset: codestyle.Preset
---@field language string the language id whose "Set from…" list shows the Preset, `general` included

---@class codestyle.SetupStore
---@field get fun(): codestyle.Setup
---@field set fun(choices?: codestyle.Setup) replaces the choices

local M = {}

---@return codestyle.SetupStore
function M.new()
  ---@type codestyle.Setup
  local choices = {}

  ---@type codestyle.SetupStore
  return {
    get = function()
      return choices
    end,
    set = function(new)
      choices = vim.deepcopy(new or {})
    end,
  }
end

return M
