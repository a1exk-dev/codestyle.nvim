-- The view model of the Arrangement Tab (ADR-0012): a pure function from the
-- spec's Arrangement data and the Draft's Arrangement to the rows of the
-- Options pane. "Rearrange when formatting" and the Keep-Together Rules are
-- checkbox rows, each rule is a row with its Slot number (later rules of a
-- Slot show `│`), and the aliases are a Group that starts folded. A spec with
-- the `sort` panel gets the sort panel instead, while it can show the shape.

local shape = require('codestyle.menu.arrangement_shape')
local view = require('codestyle.menu.view')

local M = {}

--- What a row of the Arrangement Tab stands for.
---@class codestyle.menu.ArrangementItem
---@field kind 'problem'|'note'|'enabled'|'keep'|'slots'|'rule'|'aliases'|'alias'|'sort'|'sort_order'|'custom_order'
---@field keep? string the Keep-Together kind of a `keep` row
---@field slot? integer the Slot of a `rule` row
---@field rule? integer the rule's place in its Slot
---@field alias? string the alias of an `alias` row

--- The fold id of the aliases' Group. The Group starts folded, so for it the
--- fold mark of the Menu means open.
M.ALIASES = 'Arrangement/Aliases'

--- The label of a token, a Keep-Together kind or an order.
---@param spec codestyle.ArrangementSpec
---@param id string
---@return string
function M.label(spec, id)
  return (spec.labels or {})[id] or id
end

--- The Keep-Together kinds of a spec, sorted, so the rows keep their place.
---@param spec codestyle.ArrangementSpec
---@return string[]
function M.kinds(spec)
  local kinds = vim.tbl_keys(spec.keep_together or {})
  table.sort(kinds)
  return kinds
end

---@param arrangement codestyle.Arrangement
---@param kind string
---@return codestyle.KeepTogether?
function M.keep_of(arrangement, kind)
  for _, keep in ipairs(arrangement.keep_together) do
    if keep.kind == kind then
      return keep
    end
  end
end

--- The sort panel's labels of its two orders.
M.SORT_ORDERS = { { id = 'by_name', label = 'By name' }, { id = 'custom', label = 'Custom order' } }

---@class codestyle.menu.ArrangementRowsOpts
---@field spec codestyle.ArrangementSpec
---@field arrangement codestyle.Arrangement the Arrangement that formatting uses
---@field default codestyle.Arrangement the spec's default, for the changed labels
---@field problem? codestyle.ArrangementProblem the bad part of an invalid stored Arrangement
---@field folded table<string, true> the fold ids of the Menu
---@field width integer the width of the pane
---@field query? string a filter: only the fixed rows whose label holds it, ignoring case, with breadcrumbs; Slot and alias rows are user data, which `/` finds

---@param opts codestyle.menu.ArrangementRowsOpts
---@return codestyle.menu.View
function M.rows(opts)
  local spec, arrangement, default = opts.spec, opts.arrangement, opts.default
  local value_col = math.min(36, math.floor(opts.width / 2))
  local query = opts.query and opts.query:lower()
  local b = view.builder()

  --- True when a fixed row with this label is shown; with a query, its
  --- breadcrumbs are added.
  ---@param label string
  ---@param crumbs string
  ---@param indent string the indent of the row without a query
  ---@return boolean
  local function fixed(label, crumbs, indent)
    if not query then
      b.add(indent)
      return true
    end
    if not label:lower():find(query, 1, true) then
      return false
    end
    b.add(crumbs, 'Comment')
    return true
  end

  ---@param on boolean
  ---@param label string
  ---@param changed boolean
  ---@return codestyle.menu.Span
  local function checkbox(on, label, changed)
    local span = b.add(on and '[x]' or '[ ]', 'Special')
    b.add(' ' .. label, changed and 'CodestyleChanged' or nil)
    return span
  end

  if opts.problem and not query then
    b.add(('⚠ %s: %s'):format(opts.problem.key, opts.problem.message), 'DiagnosticWarn')
    b.line({ arrangement = { kind = 'problem' } })
    b.add('  The rows show the default. An edit or X replaces the stored value.', 'Comment')
    b.line({ arrangement = { kind = 'problem' } })
  end

  local span
  if fixed('Rearrange when formatting', 'Arrangement › ', '') then
    span = checkbox(arrangement.enabled, 'Rearrange when formatting', arrangement.enabled ~= default.enabled)
    b.line({ arrangement = { kind = 'enabled' }, control = span })
  end

  local sort = spec.panel == 'sort' and shape.read_sort(arrangement)
  if sort then
    local default_sort = shape.read_sort(default)
    if fixed('Sort properties', 'Arrangement › ', '') then
      span = checkbox(sort.sort, 'Sort properties', not vim.deep_equal(sort, default_sort))
      b.line({ arrangement = { kind = 'sort' }, control = span })
    end
    if sort.sort and fixed('Order', 'Arrangement › Sort properties › ', '    ') then
      b.add('Order')
      b.pad_to(value_col)
      local label = sort.order == 'by_name' and M.SORT_ORDERS[1].label or M.SORT_ORDERS[2].label
      span = b.add(('‹%s›'):format(label), 'Constant')
      b.line({ arrangement = { kind = 'sort_order' }, control = span })
    end
    if sort.order == 'custom' and fixed('Custom order', 'Arrangement › Sort properties › ', '    ') then
      b.add('Custom order')
      b.pad_to(value_col)
      span = b.add(('[%s]'):format(table.concat(sort.names, ', ')), 'Constant')
      b.line({ arrangement = { kind = 'custom_order' }, control = span })
    end
    return b.view()
  end
  if spec.panel == 'sort' and not query then
    b.add('⚠ The sort panel cannot show this Arrangement, so it shows the Slot rows.', 'DiagnosticWarn')
    b.line({ arrangement = { kind = 'note' } })
  end

  local kinds = M.kinds(spec)
  if #kinds > 0 and not query then
    b.line()
    b.add('Keep together', 'Title')
    b.line()
  end
  for _, kind in ipairs(kinds) do
    local keep = M.keep_of(arrangement, kind)
    local default_keep = M.keep_of(default, kind)
    if fixed(M.label(spec, kind), 'Arrangement › Keep together › ', '  ') then
      span = checkbox(keep ~= nil, M.label(spec, kind), not vim.deep_equal(keep, default_keep))
      local orders = spec.keep_together[kind]
      if #orders > 1 then
        b.pad_to(value_col)
        local order = keep and keep.order or orders[1]
        b.add(('‹%s›'):format(M.label(spec, order)), keep and 'Constant' or 'Comment')
      end
      b.line({ arrangement = { kind = 'keep', keep = kind }, control = span })
    end
  end
  if query then
    return b.view()
  end

  b.line()
  b.add('Slots', 'Title')
  b.line({ arrangement = { kind = 'slots' } })
  if #arrangement.slots == 0 then
    b.add('  No Slots: o adds one.', 'Comment')
    b.line({ arrangement = { kind = 'slots' } })
  end
  for slot_index, slot in ipairs(arrangement.slots) do
    for rule_index, rule in ipairs(slot) do
      b.add(rule_index == 1 and ('%3d  '):format(slot_index) or '  │  ', 'LineNr')
      b.add(shape.summary(rule))
      b.line({ arrangement = { kind = 'rule', slot = slot_index, rule = rule_index } })
    end
  end

  b.line()
  local open = opts.folded[M.ALIASES] == true
  local names = shape.alias_names(arrangement)
  local arrow = b.add(open and '▾' or '▸', 'Title')
  b.add((' Aliases (%d)'):format(#names), 'Title')
  b.line({ arrangement = { kind = 'aliases' }, group = M.ALIASES, arrow = arrow })
  if open then
    if #names == 0 then
      b.add('  No aliases: o adds one.', 'Comment')
      b.line({ arrangement = { kind = 'aliases' } })
    end
    for _, name in ipairs(names) do
      b.add('  ' .. name)
      b.pad_to(math.min(value_col, 24))
      b.add(table.concat(vim.tbl_map(shape.summary, arrangement.aliases[name]), ' | '), 'Comment')
      b.line({ arrangement = { kind = 'alias', alias = name } })
    end
  end
  return b.view()
end

return M
