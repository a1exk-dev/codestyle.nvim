-- What a format run needs of each language it formats: the main language of
-- the buffer and every Embedded Language (ADR-0007, ADR-0008, ADR-0015). It
-- gives a language its resolved values with the values of each language it
-- `uses`, and the handlers that those languages export.

---@class codestyle.Language
---@field id string
---@field formatter codestyle.Formatter
---@field values codestyle.Values its own values, `general`, and under each used id that language's values
---@field uses table<string, table> the exported handlers of each used language
---@field parser? string the parser of an Embedded Language

--- Why an Embedded Language cannot format its part. A nil `message` is
--- silent: the Registry has already warned.
---@class codestyle.NoLanguage
---@field scope codestyle.NoticeScope
---@field key string
---@field message? string

---@class codestyle.Languages
---@field get fun(id: string): codestyle.Language a language that the Selector chose
---@field embedded fun(id: string, parser_key?: string): codestyle.Language?, codestyle.NoLanguage?

local M = {}

---@param deps { registry: codestyle.Registry, code_style: codestyle.CodeStyle }
---@return codestyle.Languages
function M.new(deps)
  local registry = deps.registry
  local cache = {} ---@type table<string, codestyle.Language>

  ---@param id string
  ---@return codestyle.Language
  local function get(id)
    if not cache[id] then
      local spec = registry.get(id) --[[@as codestyle.Spec]]
      local values = vim.tbl_extend('force', {}, deps.code_style.values(id))
      local uses = {}
      for used in pairs(spec.uses or {}) do
        values[used] = deps.code_style.values(used)
        uses[used] = registry.load(used, 'exports')
      end
      cache[id] = {
        id = id,
        formatter = registry.load(id, 'formatter') --[[@as codestyle.Formatter]],
        values = values,
        uses = uses,
      }
    end
    return cache[id]
  end

  ---@type codestyle.Languages
  return {
    get = get,
    embedded = function(id, parser_key)
      local status = registry.status(id)
      if not status then
        return nil,
          {
            scope = 'session',
            key = 'embedded:' .. id,
            message = ('no Language Plugin for the embedded language "%s" is installed; its code is kept as written'):format(
              id
            ),
          }
      end
      if status.kind == 'refused' or status.kind == 'formatting_off' then
        return nil, { scope = 'session', key = 'embedded:' .. id }
      end
      local plugin = registry.plugin(id)
      local language = get(id)
      if not language.formatter.build then
        return nil,
          {
            scope = 'buffer',
            key = id,
            message = ('%s has no Blocks for embedded code; its "%s" code is kept as written'):format(plugin, id),
          }
      end
      local parsers = registry.get(id).parsers
      local names = parser_key and parsers[parser_key] or parsers.default
      for _, name in ipairs(names) do
        if vim.treesitter.language.add(name) then
          return vim.tbl_extend('force', {}, language, { parser = name })
        end
      end
      return nil,
        {
          scope = 'buffer',
          key = id,
          message = ('%s has no Tree-sitter parser for the embedded "%s" code, which is kept as written; install one of: %s'):format(
            plugin,
            id,
            table.concat(names, ', ')
          ),
        }
    end,
  }
end

return M
