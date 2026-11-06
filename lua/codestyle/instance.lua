-- The composition root. `new` wires the Core's shared modules, and both the
-- editor instance (`get`) and `codestyle.testing` build through it, so they
-- run the same Format Run, Presets and Scheme XML import. Wiring loads no
-- Language Plugin: the Registry discovers them on first use.

local M = {}

--- The Core's shared modules, wired together. The Draft (#50 module 10),
--- Presets (module 11) and the Scheme XML import (module 12) are its public
--- seams; the Menu and `codestyle.testing` use them from here.
---@class codestyle.Services
---@field notices codestyle.Notices
---@field settings codestyle.SettingsStore
---@field registry codestyle.Registry
---@field selector codestyle.Selector
---@field store codestyle.Store
---@field format_run codestyle.FormatRun the one run behind every caller
---@field format_api codestyle.FormatApi
---@field draft fun(scope: codestyle.Scope, root?: string): codestyle.Draft?, codestyle.BrokenFile? opens a Draft of the scope's saved Code Style
---@field presets codestyle.Presets
---@field importer codestyle.SchemeImporter the pure Scheme XML importer
---@field scheme_xml codestyle.SchemeXml the Scheme XML import into a Draft (ADR-0010)

--- Wires the shared modules. Every message goes to `notify` with the
--- Notices prefix and dedup.
---@param opts { notify: fun(message: string, level: integer) }
---@return codestyle.Services
function M.new(opts)
  local notices = require('codestyle.notices').new({ notify = opts.notify })
  local settings = require('codestyle.settings').new()
  local registry = require('codestyle.registry').new({ notices = notices, api = require('codestyle').api })
  local selector = require('codestyle.selector').new({
    registry = registry,
    settings = settings.get,
    notices = notices,
  })
  local store = require('codestyle.store').new({ notices = notices, registry = registry })
  local format_run = require('codestyle.format_run').new({ registry = registry })
  local importer = require('codestyle.scheme_xml.importer').new({ registry = registry })
  ---@type codestyle.Services
  return {
    notices = notices,
    settings = settings,
    registry = registry,
    selector = selector,
    store = store,
    format_run = format_run,
    format_api = require('codestyle.format').new({
      notices = notices,
      selector = selector,
      store = store,
      format_run = format_run,
    }),
    draft = function(scope, root)
      return require('codestyle.draft').new({ store = store, registry = registry, scope = scope, root = root })
    end,
    presets = require('codestyle.presets').new({ registry = registry, settings = settings.get, notices = notices }),
    importer = importer,
    scheme_xml = require('codestyle.scheme_xml').new({ importer = importer, notices = notices }),
  }
end

--- The editor's entry points, built once over the shared modules.
---@class codestyle.Instance
---@field format fun(opts?: codestyle.FormatOpts)
---@field format_selection fun()
---@field setup fun(settings?: codestyle.Settings) keeps the settings and applies the keys
---@field keys codestyle.Keys
---@field formatexpr codestyle.Formatexpr
---@field conform codestyle.ConformAdapter
---@field health codestyle.Health
---@field menu codestyle.Menu

---@type codestyle.Instance?
local instance

---@return codestyle.Instance
function M.get()
  if not instance then
    local core = M.new({
      notify = function(message, level)
        vim.notify(message, level)
      end,
    })
    local keys = require('codestyle.keys').new({ settings = core.settings.get })
    local conform = require('codestyle.conform').new({ format_api = core.format_api })
    instance = {
      format = core.format_api.format,
      format_selection = core.format_api.format_selection,
      keys = keys,
      conform = conform,
      health = require('codestyle.health').new({
        selector = core.selector,
        registry = core.registry,
        store = core.store,
        conform = conform,
      }),
      formatexpr = require('codestyle.formatexpr').new({ format_api = core.format_api }),
      setup = function(new)
        core.settings.set(new)
        keys.apply()
      end,
      menu = require('codestyle.menu').new({
        registry = core.registry,
        store = core.store,
        selector = core.selector,
        notices = core.notices,
        draft = core.draft,
        presets = core.presets,
        scheme_xml = core.scheme_xml,
        preview = require('codestyle.preview').new({
          registry = core.registry,
          format_run = core.format_run,
        }),
      }),
    }
  end
  return instance
end

return M
