-- The Menu's view models (ADR-0004): pure functions from the specs, the Draft's
-- values and the Menu's state to the text of a pane. Each pane is drawn whole
-- from its view, so labels are buffer text and `/` finds them.

local schema = require('codestyle.schema')

local M = {}

--- What a row of a pane stands for.
---@class codestyle.menu.Item
---@field language? string the language id of a language row
---@field option? codestyle.OptionSpec the Option of an Option row, or the Group's own Option
---@field group? string the fold id of a Group's header row
---@field tab? integer the index of the Tab that holds the row
---@field control? codestyle.menu.Span where the value control of the row is: a click on it edits
---@field arrow? codestyle.menu.Span where the fold arrow of a Group is: a click on it folds

--- A part of a row: 0-based byte columns, end exclusive.
---@class codestyle.menu.Span
---@field start_col integer
---@field end_col integer

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
---@class codestyle.menu.Builder
---@field add fun(text: string, group?: string): codestyle.menu.Span adds text to the line, highlighted with `group`
---@field pad_to fun(col: integer) adds blanks up to a display column, at least one
---@field line fun(item?: codestyle.menu.Item) ends the line
---@field view fun(): codestyle.menu.View

---@return codestyle.menu.Builder
local function builder()
  local view = { lines = {}, items = {}, marks = {} } ---@type codestyle.menu.View
  local line = ''
  local self ---@type codestyle.menu.Builder
  self = {
    add = function(text, group)
      local span = { start_col = #line, end_col = #line + #text }
      if group and #text > 0 then
        table.insert(
          view.marks,
          { row = #view.lines, start_col = span.start_col, end_col = span.end_col, group = group }
        )
      end
      line = line .. text
      return span
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
    return ('‹%s›'):format(M.choice_label(option, value)), 'Constant'
  elseif option.type == 'string' then
    return ('"%s"'):format(value), 'String'
  elseif option.type == 'list' then
    return ('[%s]'):format(table.concat(vim.tbl_map(tostring, value), ', ')), 'Constant'
  end
  return table.concat(value, ' › '), 'Constant'
end

--- The label of a choice id, or the id when the Option has no such choice.
---@param option codestyle.OptionSpec
---@param id any
---@return string
function M.choice_label(option, id)
  for _, choice in ipairs(option.choices or {}) do
    if choice.id == id then
      return choice.label
    end
  end
  return tostring(id)
end

--- The value of an Option in the resolved values of its language.
---@param values codestyle.Values
---@param key string
---@return any
function M.value(values, key)
  return vim.tbl_get(values, unpack(vim.split(key, '.', { plain = true })))
end

--- The fold id of a Group: its Tab and the labels down to it.
---@param tab codestyle.Tab
---@param labels string[]
---@return string
local function group_id(tab, labels)
  return tab.name .. '/' .. table.concat(labels, '/')
end

---@class codestyle.menu.RowsOpts
---@field spec { options: codestyle.OptionSpec[] }
---@field tabs codestyle.Tab[]
---@field tab integer the index of the Tab to show
---@field query? string a filter: the Options of every Tab whose label holds it, ignoring case
---@field values codestyle.Values the resolved values of the language
---@field changed table<string, true> the keys of the changed Options (`codestyle.Draft.changed_keys`)
---@field folded table<string, true> the fold ids of the folded Groups
---@field width integer the width of the pane

--- The rows of one Tab, or with a query, the matching Options of every Tab
--- with breadcrumbs (`Tab › Group › `). A changed value has a highlighted
--- label, an Option whose requirement does not hold is dimmed, an inherited
--- value shows `Default: <value>`, and a Flagged Option is marked `⚑`.
---@param opts codestyle.menu.RowsOpts
---@return codestyle.menu.View
function M.tab_rows(opts)
  local options = {} ---@type table<string, codestyle.OptionSpec>
  for _, option in ipairs(opts.spec.options) do
    options[option.key] = option
  end
  -- The column of the values: a fixed place, or the middle of a narrow pane.
  local value_col = math.min(36, math.floor(opts.width / 2))
  local query = opts.query and opts.query:lower()
  local b = builder()

  ---@param text string
  local function matches(text)
    return query ~= nil and text:lower():find(query, 1, true) ~= nil
  end

  --- The value control of an Option, at the value column.
  ---@param option codestyle.OptionSpec
  ---@param active boolean
  ---@return codestyle.menu.Span
  local function control(option, active)
    b.pad_to(value_col)
    if option.inherit and not opts.changed[option.key] then
      return b.add(('Default: %s'):format(M.value(opts.values, option.key)), 'Comment')
    end
    local text, group = M.value_text(option, M.value(opts.values, option.key))
    return b.add(text, active and group or 'Comment')
  end

  ---@param option codestyle.OptionSpec
  ---@param active boolean
  local function label(option, text, active)
    b.add(text, not active and 'Comment' or (opts.changed[option.key] and 'CodestyleChanged' or nil))
    if option.flagged then
      b.add(' ⚑', 'DiagnosticWarn')
    end
  end

  ---@param option codestyle.OptionSpec
  ---@param depth integer
  ---@param tab integer
  ---@param crumb? string
  local function option_row(option, depth, tab, crumb)
    local active = schema.active(option, opts.values)
    b.add(('  '):rep(depth))
    if crumb then
      b.add(crumb, 'Comment')
    end
    local span
    if option.type == 'boolean' then
      local text, group = M.value_text(option, M.value(opts.values, option.key))
      span = b.add(text, active and group or 'Comment')
      label(option, ' ' .. option.label, active)
    else
      -- Under a Tab the label lines up with the labels of the checkboxes.
      label(option, (crumb and '' or '    ') .. option.label, active)
      span = control(option, active)
    end
    b.line({ option = option, tab = tab, control = span })
  end

  ---@param rows codestyle.TabRow[]
  ---@param depth integer
  ---@param tab integer
  ---@param labels string[] the labels of the Groups above
  local function walk(rows, depth, tab, labels)
    for _, row in ipairs(rows) do
      if type(row) == 'string' then
        local option = assert(options[row], 'no Option ' .. row)
        if not query then
          option_row(option, depth, tab)
        elseif matches(option.label) then
          local crumbs = vim.list_extend({ opts.tabs[tab].name }, labels)
          option_row(option, 0, tab, table.concat(crumbs, ' › ') .. ' › ')
        end
      else
        local option = row.option and assert(options[row.option], 'no Option ' .. row.option)
        local inner = vim.list_extend(vim.deepcopy(labels), { row.label })
        local id = group_id(opts.tabs[tab], inner)
        if query then
          if option and matches(row.label) then
            local crumbs = vim.list_extend({ opts.tabs[tab].name }, labels)
            b.add(table.concat(crumbs, ' › ') .. ' › ', 'Comment')
            b.add(row.label, 'Title')
            b.line({ option = option, tab = tab, control = control(option, true) })
          end
          walk(row.rows, depth, tab, inner)
        else
          local folded = opts.folded[id] == true
          b.add(('  '):rep(depth))
          local arrow = b.add(folded and '▸' or '▾', 'Title')
          b.add(' ' .. row.label, option and opts.changed[option.key] and 'CodestyleChanged' or 'Title')
          local span = option and control(option, schema.active(option, opts.values))
          b.line({ option = option, group = id, tab = tab, control = span, arrow = arrow })
          if not folded then
            walk(row.rows, depth + 1, tab, inner)
          end
        end
      end
    end
  end

  if query then
    for index, tab in ipairs(opts.tabs) do
      walk(tab.rows, 0, index, {})
    end
    if #b.view().lines == 0 then
      b.add(('  No Option matches "%s"'):format(opts.query), 'Comment')
      b.line()
    end
  else
    walk(opts.tabs[opts.tab].rows, 0, opts.tab, {})
  end
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
