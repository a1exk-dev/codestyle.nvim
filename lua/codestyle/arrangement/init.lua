-- Arrangement (ADR-0011): the port of IntelliJ's `ArrangementEngine`. It owns
-- the stored shape of a language's `arrangement` key and its validation, and
-- it matches, sorts and moves the Arrangement Entries that a Language Plugin
-- finds: Keep-Together Rules first, then each group's root goes to the rule
-- of the highest priority that matches it, then the Slots are walked in order.

local text = require('codestyle.text')

---@alias codestyle.ArrangementOrder 'keep'|'by_name'

--- One rule of a Slot: an AND of its conditions (ADR-0011). An alias's rules
--- have no `alias` and no `order`.
---@class codestyle.ArrangementRule
---@field is? string[] entry types and modifiers that the entry has
---@field is_not? string[] entry types and modifiers that the entry lacks
---@field name? string a Vim regex that the whole name matches, case-sensitive
---@field namespace? string a Vim regex that the whole namespace matches, case-sensitive
---@field alias? string the alias whose rules this rule stands for, each joined with its own conditions
---@field order? codestyle.ArrangementOrder default `keep`

--- One active Keep-Together Rule.
---@class codestyle.KeepTogether
---@field kind string a kind of the spec's `arrangement.keep_together`
---@field order string one of that kind's orders, by default its first

--- A language's Arrangement, as stored under `languages.<id>.arrangement`.
---@class codestyle.Arrangement
---@field enabled boolean rearrange in every format run ("Rearrange when formatting")
---@field aliases table<string, codestyle.ArrangementRule[]>
---@field keep_together codestyle.KeepTogether[] the active ones; the first claims shared entries
---@field slots codestyle.ArrangementRule[][]

--- An invalid stored Arrangement: the whole default is used.
---@class codestyle.ArrangementProblem
---@field key string the bad part, such as `arrangement.slots[2][1].is`
---@field message string

--- The Slot and rule that an Arrangement Entry matched, and where the entry
--- starts in the result.
---@class codestyle.ArrangementMatch
---@field language string
---@field row integer 0-based
---@field col integer
---@field end_row integer where the entry ends, 0-based
---@field end_col integer exclusive
---@field slot? integer nil when no rule matched it, as a member of another entry's Keep-Together group
---@field rule? integer the rule's place in its Slot

--- What a Language Plugin gives Arrangement: the spec's data and the code.
---@class codestyle.ArrangementPlugin
---@field spec codestyle.ArrangementSpec
---@field module codestyle.ArrangementModule

local M = {}

local RULE_KEYS = { is = true, is_not = true, name = true, namespace = true, alias = true, order = true }
local ALIAS_RULE_KEYS = { is = true, is_not = true, name = true, namespace = true }
local TOP_KEYS = { enabled = true, aliases = true, keep_together = true, slots = true }
local ORDERS = { keep = true, by_name = true }

--- The Vim regex that a rule's `name` or `namespace` becomes: a full match,
--- case-sensitive (ADR-0011).
---@param regex string
---@return string
function M.pattern(regex)
  return '\\C^\\%(' .. regex .. '\\m\\)$'
end

---@param value any
---@return string
local function show(value)
  local ok, json = pcall(vim.json.encode, value)
  return ok and json or tostring(value)
end

---@param value any
---@return boolean
local function is_object(value)
  return type(value) == 'table' and (next(value) == nil or not vim.islist(value))
end

---@param value any
---@return boolean
local function is_list(value)
  return type(value) == 'table' and vim.islist(value) and getmetatable(value) == nil
end

--- The arrangement with every Keep-Together order filled in.
---@param spec codestyle.ArrangementSpec
---@param arrangement codestyle.Arrangement
---@return codestyle.Arrangement
local function normalized(spec, arrangement)
  local result = vim.deepcopy(arrangement)
  for _, keep in ipairs(result.keep_together) do
    keep.order = keep.order or spec.keep_together[keep.kind][1]
  end
  return result
end

--- Checks a stored Arrangement; raises `{ key, message }` at the first bad part.
---@param spec codestyle.ArrangementSpec
---@param raw any
local function check(spec, raw)
  local function fail(key, message)
    error({ key = 'arrangement' .. key, message = message }, 0)
  end
  local tokens = {}
  for _, token in ipairs(vim.list_extend(vim.list_extend({}, spec.types), spec.modifiers or {})) do
    tokens[token] = true
  end
  if not is_object(raw) then
    fail('', 'expected an object')
  end
  for key in pairs(raw) do
    if not TOP_KEYS[key] then
      fail('.' .. tostring(key), 'unknown key')
    end
  end
  if raw.enabled ~= nil and type(raw.enabled) ~= 'boolean' then
    fail('.enabled', 'expected a boolean, got ' .. show(raw.enabled))
  end

  ---@param rule any
  ---@param path string
  ---@param keys table<string, boolean>
  local function check_rule(rule, path, keys)
    if not is_object(rule) then
      fail(path, 'expected a rule object')
    end
    for key in pairs(rule) do
      if not keys[key] then
        fail(path .. '.' .. tostring(key), 'unknown key')
      end
    end
    for _, key in ipairs({ 'is', 'is_not' }) do
      if rule[key] ~= nil then
        if not is_list(rule[key]) then
          fail(path .. '.' .. key, 'expected a list of tokens')
        end
        for _, token in ipairs(rule[key]) do
          if not tokens[token] then
            fail(path .. '.' .. key, 'unknown token ' .. show(token))
          end
        end
      end
    end
    for _, key in ipairs({ 'name', 'namespace' }) do
      local regex = rule[key]
      if regex ~= nil then
        if not spec[key] then
          fail(path .. '.' .. key, ('this language has no %s condition'):format(key))
        end
        if type(regex) ~= 'string' then
          fail(path .. '.' .. key, 'expected a Vim regex, got ' .. show(regex))
        end
        local ok, problem = pcall(vim.regex, M.pattern(regex))
        if not ok then
          fail(path .. '.' .. key, ('not a valid Vim regex: %s'):format(tostring(problem):gsub('^Vim:', '')))
        end
      end
    end
    if
      rule.alias ~= nil and not (type(rule.alias) == 'string' and is_object(raw.aliases) and raw.aliases[rule.alias])
    then
      fail(path .. '.alias', 'unknown alias ' .. show(rule.alias))
    end
    if rule.order ~= nil and not ORDERS[rule.order] then
      fail(path .. '.order', 'unknown order ' .. show(rule.order))
    end
  end

  if raw.aliases ~= nil then
    if not is_object(raw.aliases) then
      fail('.aliases', 'expected an object')
    end
    for name, rules in pairs(raw.aliases) do
      if not is_list(rules) or #rules == 0 then
        fail('.aliases.' .. name, 'expected a list of rules')
      end
      for index, rule in ipairs(rules) do
        check_rule(rule, ('.aliases.%s[%d]'):format(name, index), ALIAS_RULE_KEYS)
      end
    end
  end
  if raw.keep_together ~= nil then
    if not is_list(raw.keep_together) then
      fail('.keep_together', 'expected a list')
    end
    for index, keep in ipairs(raw.keep_together) do
      local path = ('.keep_together[%d]'):format(index)
      if not is_object(keep) then
        fail(path, 'expected an object')
      end
      for key in pairs(keep) do
        if key ~= 'kind' and key ~= 'order' then
          fail(path .. '.' .. tostring(key), 'unknown key')
        end
      end
      local orders = (spec.keep_together or {})[keep.kind]
      if not orders then
        fail(path .. '.kind', 'unknown kind ' .. show(keep.kind))
      end
      if keep.order ~= nil and not vim.list_contains(orders, keep.order) then
        fail(path .. '.order', 'unknown order ' .. show(keep.order))
      end
    end
  end
  if raw.slots ~= nil then
    if not is_list(raw.slots) then
      fail('.slots', 'expected a list of Slots')
    end
    for index, slot in ipairs(raw.slots) do
      if not is_list(slot) or #slot == 0 then
        fail(('.slots[%d]'):format(index), 'expected a list of rules')
      end
      for rule_index, rule in ipairs(slot) do
        check_rule(rule, ('.slots[%d][%d]'):format(index, rule_index), RULE_KEYS)
      end
    end
  end
end

--- The Arrangement that formatting uses (ADR-0011). A key that is not stored
--- comes from the default; an invalid stored value gives the whole default and
--- the bad part.
---@param spec codestyle.ArrangementSpec the spec's `arrangement` data
---@param raw any the stored value, nil when none
---@return codestyle.Arrangement
---@return codestyle.ArrangementProblem?
function M.validate(spec, raw)
  local default = normalized(spec, spec.default)
  if raw == nil then
    return default
  end
  local ok, problem = pcall(check, spec, raw)
  if not ok then
    if type(problem) ~= 'table' then
      error(problem, 0)
    end
    problem.message = problem.message .. '; the whole default Arrangement is used'
    return default, problem
  end
  local arrangement = {}
  for key in pairs(TOP_KEYS) do
    local value = raw[key]
    if value == nil then
      value = default[key]
    end
    arrangement[key] = vim.deepcopy(value)
  end
  return normalized(spec, arrangement)
end

--- True when the Arrangement names the token in a rule or an alias, or has a
--- Keep-Together Rule of that kind. A plugin asks it before a costly lookup,
--- such as the LSP for `overridden` (ADR-0011).
---@param arrangement codestyle.Arrangement
---@param token string
---@return boolean
function M.uses(arrangement, token)
  for _, keep in ipairs(arrangement.keep_together) do
    if keep.kind == token then
      return true
    end
  end
  local rules = {}
  for _, slot in ipairs(arrangement.slots) do
    vim.list_extend(rules, slot)
  end
  for _, alias in pairs(arrangement.aliases) do
    vim.list_extend(rules, alias)
  end
  for _, rule in ipairs(rules) do
    if vim.list_contains(rule.is or {}, token) or vim.list_contains(rule.is_not or {}, token) then
      return true
    end
  end
  return false
end

--- One rule after its alias is expanded, ready to match.
---@class (private) codestyle.CompiledRule
---@field slot integer
---@field rule integer
---@field index integer its place in the list of expanded rules
---@field is string[]
---@field is_not string[]
---@field names any[] `vim.regex` objects
---@field namespaces any[]
---@field order codestyle.ArrangementOrder
---@field type_atoms integer
---@field other_atoms integer

---@param arrangement codestyle.Arrangement
---@param spec codestyle.ArrangementSpec
---@return codestyle.CompiledRule[] in the order of the Slots
local function compile(arrangement, spec)
  local types = {}
  for _, type in ipairs(spec.types) do
    types[type] = true
  end
  local rules = {}
  for slot_index, slot in ipairs(arrangement.slots) do
    for rule_index, rule in ipairs(slot) do
      for _, extra in ipairs(rule.alias and arrangement.aliases[rule.alias] or { {} }) do
        local compiled = {
          slot = slot_index,
          rule = rule_index,
          index = #rules + 1,
          is = vim.list_extend(vim.list_extend({}, rule.is or {}), extra.is or {}),
          is_not = vim.list_extend(vim.list_extend({}, rule.is_not or {}), extra.is_not or {}),
          names = {},
          namespaces = {},
          order = rule.order or 'keep',
        }
        for _, source in ipairs({ rule, extra }) do
          if source.name then
            table.insert(compiled.names, vim.regex(M.pattern(source.name)))
          end
          if source.namespace then
            table.insert(compiled.namespaces, vim.regex(M.pattern(source.namespace)))
          end
        end
        local type_atoms = 0
        for _, token in ipairs(compiled.is) do
          type_atoms = type_atoms + (types[token] and 1 or 0)
        end
        compiled.type_atoms = type_atoms
        compiled.other_atoms = #compiled.is - type_atoms + #compiled.is_not + #compiled.names + #compiled.namespaces
        table.insert(rules, compiled)
      end
    end
  end
  return rules
end

---@param rule codestyle.CompiledRule
---@param entry codestyle.ArrangementEntry
---@return boolean
local function matches(rule, entry)
  local has = {}
  for _, token in ipairs(entry.types) do
    has[token] = true
  end
  for _, token in ipairs(entry.modifiers) do
    has[token] = true
  end
  for _, token in ipairs(rule.is) do
    if not has[token] then
      return false
    end
  end
  for _, token in ipairs(rule.is_not) do
    if has[token] then
      return false
    end
  end
  for _, regex in ipairs(rule.names) do
    if not entry.name or not regex:match_str(entry.name) then
      return false
    end
  end
  for _, regex in ipairs(rule.namespaces) do
    if not entry.namespace or not regex:match_str(entry.namespace) then
      return false
    end
  end
  return true
end

--- The entries sorted by name, stable: named ones by code units, then the
--- unnamed ones in their order.
---@param entries codestyle.ArrangementEntry[]
---@return codestyle.ArrangementEntry[]
local function by_name(entries)
  local position = {}
  for index, entry in ipairs(entries) do
    position[entry] = index
  end
  local sorted = vim.list_extend({}, entries)
  table.sort(sorted, function(a, b)
    if (a.name ~= nil) ~= (b.name ~= nil) then
      return a.name ~= nil
    end
    if a.name and a.name ~= b.name then
      return a.name < b.name
    end
    return position[a] < position[b]
  end)
  return sorted
end

--- The Keep-Together groups of one sibling group (IntelliJ's groupers): each
--- dependent follows its root, and a root may itself follow another root.
---@param entries codestyle.ArrangementEntry[] in text order
---@param keep_together codestyle.KeepTogether[]
---@return table<codestyle.ArrangementEntry, codestyle.ArrangementEntry> parent the root each dependent follows
---@return table<codestyle.ArrangementEntry, codestyle.ArrangementEntry[]> dependents of each root, in the order they follow it
local function groups(entries, keep_together)
  local member = {}
  for _, entry in ipairs(entries) do
    member[entry] = true
  end
  local parent, dependents = {}, {}

  ---@param entry codestyle.ArrangementEntry
  ---@param kind string
  ---@return codestyle.ArrangementEntry[]
  local function links(entry, kind)
    return vim.tbl_filter(function(linked)
      return member[linked] and linked ~= entry
    end, entry.links[kind] or {})
  end

  --- True when `entry` is `root` or one of the roots that `root` follows.
  local function above(entry, root)
    while root do
      if root == entry then
        return true
      end
      root = parent[root]
    end
    return false
  end

  --- Makes `entry` follow `root`; an entry that already follows one stays.
  local function claim(root, entry)
    if parent[entry] or above(entry, root) then
      return false
    end
    parent[entry] = root
    dependents[root] = dependents[root] or {}
    table.insert(dependents[root], entry)
    return true
  end

  for _, keep in ipairs(keep_together) do
    if keep.order == 'depth_first' or keep.order == 'breadth_first' then
      -- The roots are the entries that no other entry links to; a cycle with
      -- no such entry starts at its first entry.
      local linked = {}
      for _, entry in ipairs(entries) do
        for _, target in ipairs(links(entry, keep.kind)) do
          linked[target] = true
        end
      end
      local walked = {}
      local function walk(root)
        walked[root] = true
        local seen, order = { [root] = true }, {}
        if keep.order == 'depth_first' then
          local function visit(entry)
            for _, target in ipairs(links(entry, keep.kind)) do
              if not seen[target] then
                seen[target] = true
                table.insert(order, target)
                visit(target)
              end
            end
          end
          visit(root)
        else
          local queue, head = { root }, 1
          while queue[head] do
            for _, target in ipairs(links(queue[head], keep.kind)) do
              if not seen[target] then
                seen[target] = true
                table.insert(order, target)
                table.insert(queue, target)
              end
            end
            head = head + 1
          end
        end
        for _, target in ipairs(order) do
          if claim(root, target) then
            walked[target] = true
          end
        end
      end
      for _, entry in ipairs(entries) do
        if not linked[entry] and #links(entry, keep.kind) > 0 then
          walk(entry)
        end
      end
      for _, entry in ipairs(entries) do
        if not walked[entry] and not parent[entry] and #links(entry, keep.kind) > 0 then
          walk(entry)
        end
      end
    else
      for _, root in ipairs(entries) do
        local claimed = {}
        for _, target in ipairs(links(root, keep.kind)) do
          if claim(root, target) then
            table.insert(claimed, target)
          end
        end
        if keep.order == 'by_name' and #claimed > 0 then
          -- The group is sorted by name, and its first member is its root.
          local sorted = by_name({ root, unpack(claimed) })
          for _, target in ipairs(claimed) do
            parent[target] = nil
            table.remove(dependents[root], #dependents[root])
          end
          if #dependents[root] == 0 then
            dependents[root] = nil
          end
          local new_root = sorted[1]
          local outer = parent[root]
          if new_root ~= root and outer then
            parent[root] = nil
            parent[new_root] = outer
            for index, entry in ipairs(dependents[outer]) do
              if entry == root then
                dependents[outer][index] = new_root
              end
            end
          end
          for index = 2, #sorted do
            claim(new_root, sorted[index])
          end
        end
      end
    end
  end
  return parent, dependents
end

--- The new order of one sibling group, and the rule that each root matched.
---@param entries codestyle.ArrangementEntry[] in text order
---@param arrangement codestyle.Arrangement
---@param rules codestyle.CompiledRule[]
---@return codestyle.ArrangementEntry[] order
---@return table<codestyle.ArrangementEntry, codestyle.CompiledRule> matched
local function sort(entries, arrangement, rules)
  local parent, dependents = groups(entries, arrangement.keep_together)
  local roots = vim.tbl_filter(function(entry)
    return not parent[entry]
  end, entries)

  local by_priority = vim.list_extend({}, rules)
  table.sort(by_priority, function(a, b)
    if a.type_atoms ~= b.type_atoms then
      return a.type_atoms > b.type_atoms
    end
    if a.other_atoms ~= b.other_atoms then
      return a.other_atoms > b.other_atoms
    end
    return a.index < b.index
  end)
  local matched, buckets = {}, {}
  for _, rule in ipairs(by_priority) do
    buckets[rule] = {}
    for _, entry in ipairs(roots) do
      if not matched[entry] and matches(rule, entry) then
        matched[entry] = rule
        table.insert(buckets[rule], entry)
      end
    end
  end

  local order = {}
  local function add(entry)
    table.insert(order, entry)
    for _, dependent in ipairs(dependents[entry] or {}) do
      add(dependent)
    end
  end
  for _, rule in ipairs(rules) do
    local bucket = buckets[rule]
    for _, entry in ipairs(rule.order == 'by_name' and by_name(bucket) or bucket) do
      add(entry)
    end
  end
  for _, entry in ipairs(roots) do
    if not matched[entry] then
      add(entry)
    end
  end
  return order, matched
end

--- Rearranges the entries that `module.entries(ctx)` finds (ADR-0011). Only
--- entries that intersect `ctx.range` take part, and they move only among
--- themselves. The text between them stays where it is, except for the blank
--- lines that `module.blank_lines` asks for where the neighbours changed.
---@param ctx codestyle.ArrangementContext
---@param arrangement codestyle.Arrangement
---@param plugin codestyle.ArrangementPlugin
---@param lines string[] the text; `ctx.source` is masked in an embedded part
---@return codestyle.Edit[] edits in text order
---@return codestyle.ArrangementMatch[] matches of the entries that took part, positions after the edits
---@return codestyle.Range? span the lines that the entries that took part cover after the edits
function M.arrange(ctx, arrangement, plugin, lines)
  local source = table.concat(lines, '\n')
  local starts, offset = {}, 0
  for _, line in ipairs(lines) do
    table.insert(starts, offset)
    offset = offset + #line + 1
  end
  ---@param row integer
  ---@param col integer
  local function offset_of(row, col)
    return (starts[row + 1] or #source) + col
  end

  local range = ctx.range
  ---@param entries codestyle.ArrangementEntry[]
  ---@return codestyle.ArrangementEntry[]
  local function taking_part(entries)
    local result = vim.tbl_filter(function(entry)
      return not range or (entry.range[3] >= range.start_row and entry.range[1] <= range.end_row)
    end, entries)
    table.sort(result, function(a, b)
      return offset_of(a.range[1], a.range[2]) < offset_of(b.range[1], b.range[2])
    end)
    return result
  end

  local top = taking_part(plugin.module.entries(ctx) or {})
  if #top == 0 then
    return {}, {}, nil
  end
  local rules = compile(arrangement, plugin.spec)
  local blank_lines = plugin.module.blank_lines

  local out, length = {}, 0
  local function emit(piece)
    table.insert(out, piece)
    length = length + #piece
  end
  local found = {} ---@type { offset: integer, end_offset?: integer, rule?: codestyle.CompiledRule }[]

  ---@param entry codestyle.ArrangementEntry
  local function first(entry)
    return offset_of(entry.range[1], entry.range[2])
  end
  ---@param entry codestyle.ArrangementEntry
  local function last(entry)
    return offset_of(entry.range[3], entry.range[4])
  end

  --- The text between two neighbours. Where a neighbour changed, a gap of
  --- only whitespace gets the blank lines that the plugin asks for.
  ---@param before codestyle.ArrangementEntry
  ---@param after codestyle.ArrangementEntry
  ---@param gap string
  ---@param changed boolean
  local function between(before, after, gap, changed)
    local count = changed and blank_lines and blank_lines(before, after, ctx.values)
    if not count or count < 0 or gap:find('%S') or not gap:find('\n') then
      return gap
    end
    return ('\n'):rep(count + 1) .. gap:match('[^\n]*$')
  end

  local emit_group
  ---@param entry codestyle.ArrangementEntry
  ---@param rule? codestyle.CompiledRule
  local function emit_entry(entry, rule)
    local match = { offset = length, rule = rule }
    table.insert(found, match)
    local children = taking_part(entry.children)
    if #children == 0 then
      emit(source:sub(first(entry) + 1, last(entry)))
    else
      emit(source:sub(first(entry) + 1, first(children[1])))
      emit_group(children)
      emit(source:sub(last(children[#children]) + 1, last(entry)))
    end
    match.end_offset = length
  end
  ---@param entries codestyle.ArrangementEntry[]
  emit_group = function(entries)
    local order, matched = sort(entries, arrangement, rules)
    for index, entry in ipairs(order) do
      if index > 1 then
        local gap = source:sub(last(entries[index - 1]) + 1, first(entries[index]))
        local changed = order[index - 1] ~= entries[index - 1] or entry ~= entries[index]
        emit(between(order[index - 1], entry, gap, changed))
      end
      emit_entry(entry, matched[entry])
    end
  end

  emit(source:sub(1, first(top[1])))
  local span_start = length
  emit_group(top)
  local span_end = length
  emit(source:sub(last(top[#top]) + 1))

  local new_lines = vim.split(table.concat(out), '\n', { plain = true })
  local new_starts, new_offset = {}, 0
  for _, line in ipairs(new_lines) do
    table.insert(new_starts, new_offset)
    new_offset = new_offset + #line + 1
  end
  ---@param at integer
  ---@return integer row
  ---@return integer col
  local function position(at)
    local row = 1
    while new_starts[row + 1] and new_starts[row + 1] <= at do
      row = row + 1
    end
    return row - 1, at - new_starts[row]
  end

  local result = {} ---@type codestyle.ArrangementMatch[]
  for _, entry in ipairs(found) do
    local row, col = position(entry.offset)
    local end_row, end_col = position(entry.end_offset)
    table.insert(result, {
      language = ctx.language,
      row = row,
      col = col,
      end_row = end_row,
      end_col = end_col,
      slot = entry.rule and entry.rule.slot,
      rule = entry.rule and entry.rule.rule,
    })
  end
  table.sort(result, function(a, b)
    return a.row < b.row or (a.row == b.row and a.col < b.col)
  end)
  local span = { start_row = (position(span_start)), end_row = (position(math.max(span_start, span_end - 1))) }
  return text.diff(lines, new_lines), result, span
end

return M
