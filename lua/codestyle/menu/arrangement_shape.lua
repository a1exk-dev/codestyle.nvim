-- Pure operations of the Arrangement Tab (ADR-0012) on the stored shape of
-- ADR-0011: where a rule is, moving rules and Slots, aliases, the summary of
-- a rule, and the sort panel's reading and writing of the Slot shape. Each
-- operation returns a new Arrangement, or nil when it changes nothing.

local M = {}

--- Where a rule is: in a Slot, or in an alias.
---@class codestyle.menu.RulePlace
---@field slot? integer
---@field alias? string
---@field rule integer its place in the Slot or the alias

---@param arrangement codestyle.Arrangement
---@param place codestyle.menu.RulePlace
---@return codestyle.ArrangementRule[] the Slot or the alias that holds the rule
local function holder(arrangement, place)
  if place.alias then
    return arrangement.aliases[place.alias]
  end
  return arrangement.slots[place.slot]
end

---@param arrangement codestyle.Arrangement
---@param place codestyle.menu.RulePlace
---@return codestyle.ArrangementRule?
function M.rule(arrangement, place)
  local rules = holder(arrangement, place)
  return rules and rules[place.rule]
end

--- True when the rule has a condition: without one it matches every entry.
---@param rule codestyle.ArrangementRule
---@return boolean
function M.has_condition(rule)
  return #(rule.is or {}) > 0
    or #(rule.is_not or {}) > 0
    or rule.name ~= nil
    or rule.namespace ~= nil
    or rule.alias ~= nil
end

--- The rule with empty conditions left out, as the file stores it.
---@param rule codestyle.ArrangementRule
---@return codestyle.ArrangementRule
local function compact(rule)
  local result = vim.deepcopy(rule)
  for _, key in ipairs({ 'is', 'is_not' }) do
    if result[key] and #result[key] == 0 then
      result[key] = nil
    end
  end
  if result.order == 'keep' then
    result.order = nil
  end
  return result
end

--- Puts a rule at its place: over the rule there, or, with `insert`, as a
--- new rule there. A new rule in a Slot that does not exist yet makes the Slot.
---@param arrangement codestyle.Arrangement
---@param place codestyle.menu.RulePlace
---@param rule codestyle.ArrangementRule
---@param insert? 'rule'|'slot'|'alias' insert the rule, in a new Slot at `place.slot`, or as a new alias
---@return codestyle.Arrangement
function M.put(arrangement, place, rule, insert)
  local result = vim.deepcopy(arrangement)
  rule = compact(rule)
  if insert == 'slot' then
    table.insert(result.slots, place.slot, { rule })
  elseif insert == 'alias' then
    result.aliases[
      place.alias --[[@as string]]
    ] = { rule }
  elseif insert == 'rule' then
    table.insert(holder(result, place), place.rule, rule)
  else
    holder(result, place)[place.rule] = rule
  end
  return result
end

--- Deletes a rule; a Slot left empty goes too. An alias keeps its last rule.
---@param arrangement codestyle.Arrangement
---@param place codestyle.menu.RulePlace
---@return codestyle.Arrangement? nil when it is the last rule of an alias
function M.delete(arrangement, place)
  local result = vim.deepcopy(arrangement)
  local rules = holder(result, place)
  if place.alias and #rules == 1 then
    return nil
  end
  table.remove(rules, place.rule)
  if place.slot and #rules == 0 then
    table.remove(result.slots, place.slot)
  end
  return result
end

--- Moves a rule down (1) or up (-1). Past the edge of its Slot it joins the
--- next Slot, and a Slot left empty goes. In an alias it stops at the ends.
---@param arrangement codestyle.Arrangement
---@param place codestyle.menu.RulePlace
---@param delta 1|-1
---@return codestyle.Arrangement?
---@return codestyle.menu.RulePlace? where the rule is now
function M.move(arrangement, place, delta)
  local result = vim.deepcopy(arrangement)
  local rules = holder(result, place)
  local to = place.rule + delta
  if to >= 1 and to <= #rules then
    rules[place.rule], rules[to] = rules[to], rules[place.rule]
    return result, vim.tbl_extend('force', place, { rule = to })
  end
  if place.alias then
    return nil
  end
  local slot = place.slot + delta
  local next_slot = result.slots[slot]
  if not next_slot then
    return nil
  end
  local rule = table.remove(rules, place.rule)
  local at = delta == 1 and 1 or #next_slot + 1
  table.insert(next_slot, at, rule)
  if #rules == 0 then
    table.remove(result.slots, place.slot)
    slot = delta == 1 and place.slot or slot
  end
  return result, { slot = slot, rule = at }
end

--- Moves the whole Slot of a rule down (1) or up (-1).
---@param arrangement codestyle.Arrangement
---@param place codestyle.menu.RulePlace
---@param delta 1|-1
---@return codestyle.Arrangement?
---@return codestyle.menu.RulePlace?
function M.move_slot(arrangement, place, delta)
  if not place.slot then
    return nil
  end
  local to = place.slot + delta
  if to < 1 or to > #arrangement.slots then
    return nil
  end
  local result = vim.deepcopy(arrangement)
  result.slots[place.slot], result.slots[to] = result.slots[to], result.slots[place.slot]
  return result, { slot = to, rule = place.rule }
end

--- The Slots whose rules use an alias.
---@param arrangement codestyle.Arrangement
---@param alias string
---@return integer[]
function M.alias_users(arrangement, alias)
  local slots = {}
  for index, slot in ipairs(arrangement.slots) do
    for _, rule in ipairs(slot) do
      if rule.alias == alias and not vim.list_contains(slots, index) then
        table.insert(slots, index)
      end
    end
  end
  return slots
end

--- Renames an alias and every rule that uses it.
---@param arrangement codestyle.Arrangement
---@param from string
---@param to string
---@return codestyle.Arrangement
function M.rename_alias(arrangement, from, to)
  local result = vim.deepcopy(arrangement)
  result.aliases[to], result.aliases[from] = result.aliases[from], nil
  for _, slot in ipairs(result.slots) do
    for _, rule in ipairs(slot) do
      if rule.alias == from then
        rule.alias = to
      end
    end
  end
  return result
end

--- The aliases' names, sorted.
---@param arrangement codestyle.Arrangement
---@return string[]
function M.alias_names(arrangement)
  local names = vim.tbl_keys(arrangement.aliases)
  table.sort(names)
  return names
end

--- The readable summary of a rule's conditions (ADR-0012), such as
--- `method  !static  name /get.*/  by name`.
---@param rule codestyle.ArrangementRule
---@return string
function M.summary(rule)
  local parts = {}
  vim.list_extend(parts, rule.is or {})
  for _, token in ipairs(rule.is_not or {}) do
    table.insert(parts, '!' .. token)
  end
  if rule.name then
    table.insert(parts, ('name /%s/'):format(rule.name))
  end
  if rule.namespace then
    table.insert(parts, ('namespace /%s/'):format(rule.namespace))
  end
  if rule.alias then
    table.insert(parts, 'alias ' .. rule.alias)
  end
  if #parts == 0 then
    table.insert(parts, 'any entry')
  end
  if rule.order == 'by_name' then
    table.insert(parts, 'by name')
  end
  return table.concat(parts, '  ')
end

-- The sort panel (ADR-0012): off is no Slots, "by name" is one Slot with one
-- by-name rule that every named entry matches, and "custom order" is one Slot
-- per name, with a name regex that matches only that name.

--- The sort panel's view of an Arrangement.
---@class codestyle.menu.Sort
---@field sort boolean
---@field order? 'by_name'|'custom'
---@field names? string[] the custom order

local BY_NAME = { name = '.*', order = 'by_name' }

--- The characters that are special in a Vim regex in 'magic' mode.
local SPECIAL = '\\.*[]~^$'

--- The regex that matches only this name.
---@param name string
---@return string
local function literal(name)
  return vim.fn.escape(name, SPECIAL)
end

--- The name that a regex of `literal` matches, or nil for another regex.
---@param regex string
---@return string?
local function name_of(regex)
  local name = regex:gsub('\\(.)', '%1')
  return literal(name) == regex and name or nil
end

--- What the sort panel shows, or nil when the shape is not one it can show.
---@param arrangement codestyle.Arrangement
---@return codestyle.menu.Sort?
function M.read_sort(arrangement)
  if next(arrangement.aliases) ~= nil then
    return nil
  end
  local slots = arrangement.slots
  if #slots == 0 then
    return { sort = false }
  end
  if #slots == 1 and #slots[1] == 1 and vim.deep_equal(slots[1][1], BY_NAME) then
    return { sort = true, order = 'by_name' }
  end
  local names = {}
  for _, slot in ipairs(slots) do
    local rule = slot[1]
    local name = #slot == 1 and vim.deep_equal(vim.tbl_keys(rule), { 'name' }) and name_of(rule.name)
    if not name then
      return nil
    end
    table.insert(names, name)
  end
  return { sort = true, order = 'custom', names = names }
end

--- The Arrangement with the Slots that the sort panel's choice stands for.
---@param arrangement codestyle.Arrangement
---@param sort codestyle.menu.Sort
---@return codestyle.Arrangement
function M.write_sort(arrangement, sort)
  local result = vim.deepcopy(arrangement)
  result.slots = {}
  if sort.sort and sort.order == 'by_name' then
    result.slots = { { vim.deepcopy(BY_NAME) } }
  elseif sort.sort then
    for _, name in ipairs(sort.names or {}) do
      table.insert(result.slots, { { name = literal(name) } })
    end
  end
  return result
end

return M
