-- The Language Selector (ADR-0015): it chooses the Language Plugin and the
-- parser for a buffer, in three steps that stop at the first answer: the
-- user's override, the filetype claim, then each spec's `match(buf)`.
-- Nothing is cached, because `match(buf)` may read text that changes.

---@class codestyle.Choice
---@field language string the language id
---@field parser string

---@alias codestyle.NoChoiceReason
---| 'no_claim' no plugin claims the buffer
---| 'disabled' the user turned codestyle off for the filetype
---| 'conflict' two plugins claim the buffer at the same step
---| 'refused' the chosen plugin is refused (the Registry warned)
---| 'formatting_off' the chosen plugin does not format (the Registry warned)
---| 'no_parser' none of the chosen plugin's parsers is installed

---@class codestyle.NoChoice
---@field reason codestyle.NoChoiceReason
---@field filetype string
---@field language? string the chosen language id, for `refused`, `formatting_off` and `no_parser`
---@field message string what the user reads

---@class codestyle.Selector
---@field choose fun(buf: integer): codestyle.Choice?, codestyle.NoChoice?

local M = {}

--- The keys that stand for a filetype, as `vim.treesitter.language.get_lang`
--- tries them: the whole name, then the part before the first dot.
---@param filetype string
---@return string[]
local function filetype_keys(filetype)
  local base = filetype:match('^([^.]+)%.')
  return base and { filetype, base } or { filetype }
end

--- A `match(buf)` that is true when the buffer's file name matches one of the
--- globs, as PhpStorm assigns file names to a language (ADR-0015).
---@param globs string[] such as `{ 'phpunit.xml.dist', '*.es6' }`
---@return fun(buf: integer): boolean
function M.match_globs(globs)
  local patterns = vim.tbl_map(vim.glob.to_lpeg, globs)
  return function(buf)
    local name = vim.fs.basename(vim.api.nvim_buf_get_name(buf))
    if name == '' then
      return false
    end
    for _, pattern in ipairs(patterns) do
      if pattern:match(name) then
        return true
      end
    end
    return false
  end
end

---@param deps { registry: codestyle.Registry, setup: (fun(): codestyle.Setup), notices: codestyle.Notices }
---@return codestyle.Selector
function M.new(deps)
  local registry = deps.registry

  ---@param ids string[] two or more
  ---@param filetype string
  ---@return codestyle.NoChoice
  local function conflict(ids, filetype)
    local plugins = vim.tbl_map(registry.plugin, ids)
    local pick = filetype == '' and ('vim.b.codestyle_language = "%s"'):format(ids[1])
      or ('setup{ filetypes = { ["%s"] = "%s" } }'):format(filetype, ids[1])
    return {
      reason = 'conflict',
      filetype = filetype,
      message = ('%s %s claim the filetype "%s", so none formats it; pick one with %s'):format(
        table.concat(plugins, ' and '),
        #plugins == 2 and 'both' or 'all',
        filetype,
        pick
      ),
    }
  end

  ---@param id string
  ---@return boolean
  local function refused(id)
    return registry.status(id).kind == 'refused'
  end

  --- The ids whose spec lists the filetype: the whole name first, then the
  --- base. A refused spec claims only when no other spec does, so that its
  --- filetype is not reported as unclaimed on top of the Registry's warning.
  ---@param filetype string
  ---@return string[]
  local function claims(filetype)
    if filetype == '' then
      return {}
    end
    for _, key in ipairs(filetype_keys(filetype)) do
      local ids = vim.tbl_filter(function(id)
        return vim.list_contains(registry.get(id).filetypes or {}, key)
      end, registry.languages())
      if #ids > 0 then
        local usable = vim.tbl_filter(function(id)
          return not refused(id)
        end, ids)
        return #usable > 0 and usable or { ids[1] }
      end
    end
    return {}
  end

  ---@param buf integer
  ---@return string[]
  local function matches(buf)
    return vim.tbl_filter(function(id)
      local spec = registry.get(id) --[[@as codestyle.Spec]]
      if not spec.match or refused(id) then
        return false
      end
      local ok, result = pcall(spec.match, buf)
      if not ok then
        deps.notices.report(
          vim.log.levels.WARN,
          'session',
          'match:' .. id,
          ('the match function of %s raised an error: %s'):format(registry.plugin(id), result)
        )
        return false
      end
      return result == true
    end, registry.languages())
  end

  ---@param buf integer
  ---@param filetype string
  ---@return string|false|nil override the language id, `false` for off, nil for none
  local function override(buf, filetype)
    local id = vim.b[buf].codestyle_language
    if id ~= nil then
      return id
    end
    local filetypes = deps.setup().filetypes or {}
    for _, key in ipairs(filetype_keys(filetype)) do
      if filetypes[key] ~= nil then
        return filetypes[key]
      end
    end
  end

  ---@param id string
  ---@param filetype string
  ---@return codestyle.Choice?, codestyle.NoChoice?
  local function with_parser(id, filetype)
    local status = registry.status(id)
    if not status then
      return nil,
        {
          reason = 'no_claim',
          filetype = filetype,
          message = ('the language "%s" that the override picks has no installed Language Plugin'):format(id),
        }
    end
    if status.kind == 'refused' or status.kind == 'formatting_off' then
      return nil, { reason = status.kind, filetype = filetype, language = id, message = status.reason }
    end
    local parsers = registry.get(id).parsers
    local names
    for _, key in ipairs(vim.list_extend(filetype_keys(filetype), { 'default' })) do
      names = names or parsers[key]
    end
    for _, name in ipairs(names) do
      if vim.treesitter.language.add(name) then
        return { language = id, parser = name }
      end
    end
    return nil,
      {
        reason = 'no_parser',
        filetype = filetype,
        language = id,
        message = ('%s has no Tree-sitter parser for this buffer; install one of: %s'):format(
          registry.plugin(id),
          table.concat(names, ', ')
        ),
      }
  end

  ---@type codestyle.Selector
  return {
    choose = function(buf)
      local filetype = vim.bo[buf].filetype
      local id = override(buf, filetype)
      if id == false then
        return nil,
          { reason = 'disabled', filetype = filetype, message = ('formatting is off for "%s"'):format(filetype) }
      end
      if id then
        return with_parser(id, filetype)
      end
      local ids = claims(filetype)
      if #ids == 0 then
        ids = matches(buf)
      end
      if #ids > 1 then
        return nil, conflict(ids, filetype)
      end
      if #ids == 1 then
        return with_parser(ids[1], filetype)
      end
      return nil,
        {
          reason = 'no_claim',
          filetype = filetype,
          message = ('no Language Plugin claims the filetype "%s"'):format(filetype),
        }
    end,
  }
end

return M
