-- The Menu's view models (ADR-0004): pure functions from the specs, the Draft's
-- values and the Menu's state to the text of a pane. Each pane is drawn whole
-- from its view, so labels are buffer text and `/` finds them.

local M = {}

--- What a row of a pane stands for.
---@class codestyle.menu.Item
---@field language? string the language id of a language row
---@field option? codestyle.OptionSpec the Option of an Option row, or the Group's own Option

--- A highlight of a part of a row: 0-based row and byte columns, end exclusive.
---@class codestyle.menu.Mark
---@field row integer
---@field start_col integer
---@field end_col integer
---@field group string

--- The text of one pane.
---@class codestyle.menu.View
---@field lines string[]
---@field items table<integer, codestyle.menu.Item> by 1-based row
---@field marks codestyle.menu.Mark[]

--- Builds the lines of a pane one part at a time.
---@return { add: fun(text: string, group?: string), pad_to: fun(col: integer), line: fun(item?: codestyle.menu.Item), view: fun(): codestyle.menu.View }
local function builder()
  local view = { lines = {}, items = {}, marks = {} } ---@type codestyle.menu.View
  local line = ''
  local self
  self = {
    add = function(text, group)
      if group and #text > 0 then
        table.insert(view.marks, { row = #view.lines, start_col = #line, end_col = #line + #text, group = group })
      end
      line = line .. text
    end,
    pad_to = function(col)
      self.add((' '):rep(math.max(1, col - vim.fn.strdisplaywidth(line))))
    end,
    line = function(item)
      table.insert(view.lines, line)
      view.items[#view.lines] = item
      line = ''
    end,
    view = function()
      return view
    end,
  }
  return self
end

--- A language row of the language list.
---@class codestyle.menu.Language
---@field id string
---@field name string
---@field changed integer the `•N` count of the Draft

---@param opts { scope: codestyle.Scope, languages: codestyle.menu.Language[], kept: codestyle.KeptLanguage[] }
---@return codestyle.menu.View
function M.languages(opts)
  local b = builder()
  b.add(opts.scope == 'project' and 'Project Code Style' or 'Global Code Style', 'Title')
  b.line()
  b.line()
  for _, language in ipairs(opts.languages) do
    b.add(language.name)
    if language.changed > 0 then
      b.add(' ')
      b.add(('•%d'):format(language.changed), 'CodestyleChanged')
    end
    b.line({ language = language.id })
  end
  if #opts.kept > 0 then
    b.line()
  end
  for _, kept in ipairs(opts.kept) do
    b.add(('⚠ %s: not installed, %d kept values'):format(kept.id, kept.count), 'DiagnosticWarn')
    b.line()
  end
  return b.view()
end

--- The Tabs of a spec; a spec without Tabs gets one with every Option.
---@param spec { options: codestyle.OptionSpec[], tabs?: codestyle.Tab[] }
---@return codestyle.Tab[]
function M.tabs(spec)
  if spec.tabs and #spec.tabs > 0 then
    return spec.tabs
  end
  return {
    {
      name = 'Options',
      rows = vim.tbl_map(function(option)
        return option.key
      end, spec.options),
    },
  }
end

--- The control that shows a value, and its highlight group.
---@param option codestyle.OptionSpec
---@param value any
---@return string text
---@return string group
function M.value_text(option, value)
  if option.type == 'boolean' then
    return value and '[x]' or '[ ]', 'Special'
  elseif option.type == 'integer' then
    return ('[ %d ]'):format(value), 'Number'
  elseif option.type == 'choice' then
    for _, choice in ipairs(option.choices or {}) do
      if choice.id == value then
        return ('‹%s›'):format(choice.label), 'Constant'
      end
    end
    return ('‹%s›'):format(tostring(value)), 'Constant'
  elseif option.type == 'string' then
    return ('"%s"'):format(value), 'String'
  elseif option.type == 'list' then
    return ('[%s]'):format(table.concat(vim.tbl_map(tostring, value), ', ')), 'Constant'
  end
  return table.concat(value, ' › '), 'Constant'
end

--- The rows of one Tab.
---@param opts { spec: { options: codestyle.OptionSpec[] }, tab: codestyle.Tab, values: codestyle.Values, width: integer }
---@return codestyle.menu.View
function M.tab_rows(opts)
  local options = {} ---@type table<string, codestyle.OptionSpec>
  for _, option in ipairs(opts.spec.options) do
    options[option.key] = option
  end
  -- The column of the values: a fixed place, or the middle of a narrow pane.
  local value_col = math.min(36, math.floor(opts.width / 2))
  local b = builder()

  ---@param option codestyle.OptionSpec
  local function value(option)
    return vim.tbl_get(opts.values, unpack(vim.split(option.key, '.', { plain = true })))
  end

  ---@param option codestyle.OptionSpec
  ---@param depth integer
  local function option_row(option, depth)
    b.add(('  '):rep(depth))
    local text, group = M.value_text(option, value(option))
    if option.type == 'boolean' then
      b.add(text, group)
      b.add(' ' .. option.label)
    else
      b.add('    ' .. option.label)
      b.pad_to(value_col)
      b.add(text, group)
    end
    b.line({ option = option })
  end

  ---@param rows codestyle.TabRow[]
  ---@param depth integer
  local function walk(rows, depth)
    for _, row in ipairs(rows) do
      if type(row) == 'string' then
        option_row(assert(options[row], 'no Option ' .. row), depth)
      else
        local option = row.option and assert(options[row.option], 'no Option ' .. row.option)
        b.add(('  '):rep(depth))
        b.add('▾ ' .. row.label, 'Title')
        if option then
          b.pad_to(value_col)
          b.add(M.value_text(option, value(option)))
        end
        b.line({ option = option })
        walk(row.rows, depth + 1)
      end
    end
  end
  walk(opts.tab.rows, 0)
  return b.view()
end

--- The Tab strip of the Options pane's winbar. A click on a Tab calls
--- `click` with the Tab's index.
---@param tabs codestyle.Tab[]
---@param active integer
---@param click string the Vim function name of the click handler
---@return string
function M.tab_strip(tabs, active, click)
  local parts = {}
  for index, tab in ipairs(tabs) do
    local group = index == active and '%#TabLineSel#' or '%#TabLine#'
    table.insert(parts, ('%s%%%d@%s@ %s %%X'):format(group, index, click, (tab.name:gsub('%%', '%%%%'))))
  end
  -- `%<` cuts a strip that is too long at its end, so the first Tab stays.
  return table.concat(parts, '%#WinBar# ') .. '%#WinBar#%<'
end

return M
