-- `:checkhealth codestyle` (ADR-0014): for each open buffer that a Language
-- Plugin claims, it lists why the buffer is not formatted, and what else
-- changes its text: other conform formatters, LSP clients that format, and
-- editorconfig's trim when "Keep indents on empty lines" is on. It changes
-- nothing.

---@class codestyle.Health
---@field check fun()

local M = {}

--- The entry that `:checkhealth codestyle` calls.
function M.check()
  require('codestyle.instance').get().health.check()
end

---@param buf integer
---@return string
local function label(buf)
  local name = vim.api.nvim_buf_get_name(buf)
  local shown = name == '' and ('buffer %d'):format(buf) or vim.fn.fnamemodify(name, ':~:.')
  return ('%s (%s)'):format(shown, vim.bo[buf].filetype)
end

--- The value of an Option key such as `indent.keep_on_empty_lines` in nested values.
---@param values codestyle.Values
---@param key string
---@return any
local function value_at(values, key)
  local value = values
  for _, part in ipairs(vim.split(key, '.', { plain = true })) do
    if type(value) ~= 'table' then
      return nil
    end
    value = value[part]
  end
  return value
end

---@param deps { selector: codestyle.Selector, registry: codestyle.Registry, store: codestyle.Store, conform: codestyle.ConformAdapter }
---@return codestyle.Health
function M.new(deps)
  ---@param buf integer
  ---@return string[]
  local function other_conform_formatters(buf)
    deps.conform.register()
    local conform = package.loaded.conform
    if not conform then
      return {}
    end
    return vim.tbl_filter(function(name)
      return name ~= 'codestyle'
    end, conform.list_formatters_for_buffer(buf))
  end

  ---@param buf integer
  ---@return string[]
  local function formatting_clients(buf)
    local names = {}
    for _, client in ipairs(vim.lsp.get_clients({ bufnr = buf })) do
      if
        client:supports_method('textDocument/formatting', buf)
        or client:supports_method('textDocument/rangeFormatting', buf)
      then
        table.insert(names, client.name)
      end
    end
    return names
  end

  ---@param buf integer
  ---@param language string
  ---@return boolean
  local function trim_strips_kept_indents(buf, language)
    local editorconfig = vim.b[buf].editorconfig
    local key = deps.registry.get(language).keep_indents_on_empty_lines
    if type(editorconfig) ~= 'table' or editorconfig.trim_trailing_whitespace ~= 'true' or not key then
      return false
    end
    local code_style = deps.store.for_buffer(buf)
    return code_style ~= nil and value_at(code_style.values(language), key) == true
  end

  ---@param buf integer
  local function check_buffer(buf)
    local choice, no_choice = deps.selector.choose(buf)
    if not choice then
      ---@cast no_choice codestyle.NoChoice
      if no_choice.reason ~= 'no_claim' and no_choice.reason ~= 'disabled' then
        vim.health.warn(('%s: %s'):format(label(buf), no_choice.message))
      end
      return
    end
    vim.health.ok(
      ('%s: %s formats it with the parser "%s"'):format(
        label(buf),
        deps.registry.plugin(choice.language),
        choice.parser
      )
    )
    local formatters = other_conform_formatters(buf)
    if #formatters > 0 then
      vim.health.warn(
        ('%s: conform.nvim also runs %s on this buffer'):format(label(buf), table.concat(formatters, ', ')),
        'they can change what codestyle writes; remove them from formatters_by_ft for this filetype'
      )
    end
    for _, name in ipairs(formatting_clients(buf)) do
      vim.health.warn(
        ('%s: the LSP client %s can format this buffer'):format(label(buf), name),
        'a format key or format-on-save that falls back to LSP gives other output than codestyle'
      )
    end
    if trim_strips_kept_indents(buf, choice.language) then
      vim.health.warn(
        ('%s: editorconfig trim_trailing_whitespace removes the indents that '):format(label(buf))
          .. '"Keep indents on empty lines" keeps, when the file is saved',
        'set trim_trailing_whitespace = false in .editorconfig, or turn off "Keep indents on empty lines"'
      )
    end
  end

  ---@type codestyle.Health
  return {
    check = function()
      vim.health.start('Buffers that a Language Plugin claims')
      for _, buf in ipairs(vim.api.nvim_list_bufs()) do
        if vim.api.nvim_buf_is_loaded(buf) and vim.bo[buf].buflisted then
          check_buffer(buf)
        end
      end
    end,
  }
end

return M
