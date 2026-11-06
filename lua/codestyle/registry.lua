-- The Language Registry (ADR-0007): it finds the spec of every installed
-- Language Plugin on the runtimepath on first use, refuses a broken or
-- clashing spec with one warning, and requires a plugin's lazy modules only
-- when they are needed.

---@alias codestyle.SpecPart
---| 'formatter' the module that `spec.formatter` names
---| 'exports' the module that `spec.exports.module` names, or `{}` when it names none

---@alias codestyle.StatusKind
---| 'ok'
---| 'deprecated' the spec has the previous `api`; it works
---| 'refused' the Core does not use the spec
---| 'formatting_off' the plugin is listed, but it does not format

---@class codestyle.Status
---@field kind codestyle.StatusKind
---@field reason? string why, for every kind but `ok`

---@class codestyle.Registry
---@field languages fun(): string[] the ids of every loaded spec, refused ones too, sorted; check `status`
---@field get fun(id: string): codestyle.Spec?
---@field plugin fun(id: string): string? the plugin name (its folder)
---@field status fun(id: string): codestyle.Status? nil when no loaded spec has the id
---@field load fun(id: string, part: codestyle.SpecPart): any the required module that the spec names for `part`

local M = {}

--- The id of the Core's own Options (ADR-0003, ADR-0018), which no plugin may use.
local RESERVED_ID = 'general'

--- The name of the plugin that ships the spec file: the folder above `lua/`.
---@param path string `<plugin>/lua/codestyle/languages/<id>.lua`
---@return string
local function plugin_name(path)
  return vim.fn.fnamemodify(path, ':h:h:h:h:t')
end

---@param deps { notices: codestyle.Notices, api: integer }
---@return codestyle.Registry
function M.new(deps)
  ---@class codestyle.Entry
  ---@field spec codestyle.Spec
  ---@field plugin string
  ---@field status codestyle.Status

  ---@type table<string, codestyle.Entry>
  local entries = {}
  local discovered = false

  ---@param key string
  ---@param message string
  local function warn(key, message)
    deps.notices.report(vim.log.levels.WARN, 'session', 'registry:' .. key, message)
  end

  ---@param plugin string
  ---@param reason string
  local function refuse(plugin, reason)
    warn(plugin .. ':refused', ('%s is refused: %s'):format(plugin, reason))
  end

  ---@param path string
  local function add(path)
    local plugin = plugin_name(path)
    local ok, spec = pcall(dofile, path)
    if not ok or type(spec) ~= 'table' or type(spec.id) ~= 'string' then
      refuse(plugin, ('its spec %s does not load: %s'):format(path, ok and 'no id' or tostring(spec)))
      return
    end
    ---@cast spec codestyle.Spec
    if spec.id == RESERVED_ID then
      refuse(plugin, ('the language id "%s" is reserved for the Core'):format(RESERVED_ID))
      return
    end
    if entries[spec.id] then
      refuse(plugin, ('its language id "%s" is already used by %s'):format(spec.id, entries[spec.id].plugin))
      return
    end
    local status = { kind = 'ok' }
    if spec.api == deps.api - 1 then
      status = { kind = 'deprecated', reason = ('it has the deprecated api %d'):format(spec.api) }
      warn(
        plugin .. ':api',
        ('%s has the deprecated api %d; it works for now, but update it to api %d'):format(plugin, spec.api, deps.api)
      )
    elseif spec.api ~= deps.api then
      -- Kept as refused, so its filetypes are not reported as unclaimed.
      local reason = ('it has the unknown api %s; the Core has api %d'):format(tostring(spec.api), deps.api)
      status = { kind = 'refused', reason = reason }
      refuse(plugin, reason)
    end
    entries[spec.id] = { spec = spec, plugin = plugin, status = status }
  end

  --- Turns formatting off for a plugin whose `uses` plugin is missing or
  --- exports another version. Every spec is known by now.
  ---@param entry codestyle.Entry
  local function check_uses(entry)
    local used_ids = vim.tbl_keys(entry.spec.uses or {})
    table.sort(used_ids)
    for _, used_id in ipairs(used_ids) do
      local version = entry.spec.uses[used_id]
      local used = entries[used_id]
      local reason
      if not used then
        reason = ('it uses the language "%s", which no installed plugin has'):format(used_id)
      elseif used.status.kind == 'refused' then
        reason = ('it uses %s, which is refused'):format(used.plugin)
      elseif not used.spec.exports or used.spec.exports.version ~= version then
        reason = ('it uses version %d of %s, which exports %s'):format(
          version,
          used.plugin,
          used.spec.exports and ('version %d'):format(used.spec.exports.version) or 'nothing'
        )
      end
      if reason then
        entry.status = { kind = 'formatting_off', reason = reason }
        warn(entry.plugin .. ':uses', ('%s does not format: %s'):format(entry.plugin, reason))
        return
      end
    end
  end

  ---@return table<string, codestyle.Entry>
  local function discover()
    if not discovered then
      discovered = true
      for _, path in ipairs(vim.api.nvim_get_runtime_file('lua/codestyle/languages/*.lua', true)) do
        add(path)
      end
      local ids = vim.tbl_keys(entries)
      table.sort(ids)
      for _, id in ipairs(ids) do
        if entries[id].status.kind ~= 'refused' then
          check_uses(entries[id])
        end
      end
    end
    return entries
  end

  ---@type codestyle.Registry
  return {
    languages = function()
      local ids = vim.tbl_keys(discover())
      table.sort(ids)
      return ids
    end,
    get = function(id)
      local entry = discover()[id]
      return entry and entry.spec
    end,
    plugin = function(id)
      local entry = discover()[id]
      return entry and entry.plugin
    end,
    status = function(id)
      local entry = discover()[id]
      return entry and entry.status
    end,
    load = function(id, part)
      local spec = discover()[id].spec
      if part == 'exports' then
        local module = spec.exports and spec.exports.module
        return module and require(module) or {}
      end
      return require(spec[part])
    end,
  }
end

return M
