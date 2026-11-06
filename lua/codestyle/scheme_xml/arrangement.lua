-- The import of a language's `<arrangement>` element (ADR-0011): tokens,
-- Keep-Together kinds and orders go through the spec's `phpstorm` map, Java
-- regexes through Regex Conversion. What it cannot convert is left out and
-- named: `<OR>` and nesting, unknown tokens and kinds, regexes, and Slot
-- comment text.

local regex_conversion = require('codestyle.regex_conversion')

--- A part of the Scheme XML that the import could not convert.
---@class codestyle.NotConverted
---@field part string
---@field reason string

local M = {}

--- PhpStorm's order ids; a spec's `phpstorm` map may add to them.
local ORDERS = { KEEP = 'keep', BY_NAME = 'by_name', DEPTH_FIRST = 'depth_first', BREADTH_FIRST = 'breadth_first' }

--- PhpStorm's regex conditions and the rule keys they become.
local REGEX_KEYS = { NAME = 'name', NAMESPACE = 'namespace', XML_NAMESPACE = 'namespace' }

---@param element codestyle.XmlElement
---@param name string
---@return codestyle.XmlElement?
local function child(element, name)
  for _, each in ipairs(element.children) do
    if each.name == name then
      return each
    end
  end
end

--- The stored Arrangement (ADR-0011) of an `<arrangement>` element. Only the
--- keys that the element has are set, so the others come from the default.
---@param spec codestyle.ArrangementSpec
---@param element codestyle.XmlElement
---@return table raw
---@return codestyle.NotConverted[]
function M.convert(spec, element)
  local map = spec.phpstorm or {}
  local skipped = {} ---@type codestyle.NotConverted[]
  local function skip(part, reason)
    table.insert(skipped, { part = 'arrangement: ' .. part, reason = reason })
  end
  local tokens = {} ---@type table<string, true>
  for _, token in ipairs(vim.list_extend(vim.list_extend({}, spec.types), spec.modifiers or {})) do
    tokens[token] = true
  end

  ---@param rule_element codestyle.XmlElement
  ---@param aliases? table<string, any> the aliases a Slot rule may name; nil for an alias's own rules
  ---@return codestyle.ArrangementRule?
  ---@return string? why not
  local function rule(rule_element, aliases)
    local match = child(rule_element, 'match')
    if not match then
      return nil, 'a rule without <match>'
    end
    local result = {} ---@type codestyle.ArrangementRule
    if #match.children > 1 then
      return nil, 'a <match> with more than one condition'
    end
    local condition = match.children[1]
    local atoms = {}
    if condition and condition.name == 'AND' then
      atoms = condition.children
    elseif condition then
      atoms = { condition }
    end
    for _, atom in ipairs(atoms) do
      local value = vim.trim(atom.text)
      if atom.name == 'AND' or atom.name == 'OR' then
        return nil, ('cannot convert %s<%s>'):format(atom == condition and '' or 'a nested ', atom.name)
      elseif REGEX_KEYS[atom.name] then
        local key = REGEX_KEYS[atom.name]
        if not spec[key] then
          return nil, ('this language has no %s condition'):format(key)
        end
        local converted, reason = regex_conversion.from_java(atom.text)
        if not converted then
          return nil, ('cannot convert the Java regex "%s": %s'):format(atom.text, reason)
        end
        result[key] = converted
      elseif aliases and aliases[atom.name] and value == '' then
        if result.alias then
          return nil, 'more than one alias'
        end
        result.alias = atom.name
      else
        local token = map[atom.name]
        if not token or not tokens[token] then
          return nil, 'unknown token ' .. atom.name
        end
        local key = (value == '' or value == 'true') and 'is' or value == 'false' and 'is_not' or nil
        if not key then
          return nil, ('the token %s has the value "%s"'):format(atom.name, value)
        end
        result[key] = result[key] or {}
        table.insert(result[key], token)
      end
    end
    local order = child(rule_element, 'order')
    if aliases and order then
      local id = vim.trim(order.text)
      if id == 'BY_NAME' then
        result.order = 'by_name'
      elseif id ~= 'KEEP' then
        return nil, 'unknown order ' .. id
      end
    end
    return result
  end

  local raw = {}
  local tokens_element = child(element, 'tokens')
  if tokens_element then
    raw.aliases = {}
    for _, token in ipairs(tokens_element.children) do
      local id = token.attrs.id or token.attrs.name or '?'
      local rules = {}
      for index, rule_element in ipairs((child(token, 'rules') or { children = {} }).children) do
        local converted, why = rule(rule_element)
        if converted then
          table.insert(rules, converted)
        else
          skip(('alias %s rule %d'):format(id, index), why)
        end
      end
      if #rules > 0 then
        raw.aliases[id] = rules
      end
    end
    if next(raw.aliases) == nil then
      raw.aliases = vim.empty_dict()
    end
  end
  local aliases = raw.aliases or spec.default.aliases or {}

  local groups = child(element, 'groups')
  if groups then
    raw.keep_together = {}
    for _, group in ipairs(groups.children) do
      local type_id = vim.trim((child(group, 'type') or { text = '' }).text)
      local order_id = vim.trim((child(group, 'order') or { text = '' }).text)
      local kind = map[type_id]
      local orders = kind and (spec.keep_together or {})[kind]
      local order = map[order_id] or ORDERS[order_id]
      if not orders then
        skip('Keep-Together ' .. type_id, 'unknown Keep-Together kind')
      elseif order_id ~= '' and not vim.list_contains(orders, order) then
        skip('Keep-Together ' .. type_id, 'unknown order ' .. order_id)
      else
        table.insert(raw.keep_together, { kind = kind, order = order })
      end
    end
  end

  local rules = child(element, 'rules')
  if rules then
    raw.slots = {}
    for slot_index, section in ipairs(rules.children) do
      local rule_elements = section.name == 'rule' and { section } or {}
      local commented = false
      for _, each in ipairs(section.name == 'section' and section.children or {}) do
        if each.name == 'rule' then
          table.insert(rule_elements, each)
        elseif (each.name == 'start_comment' or each.name == 'end_comment') and not commented then
          commented = true
          skip(('Slot %d comment'):format(slot_index), 'Slot comments are not kept')
        end
      end
      local slot = {}
      for rule_index, rule_element in ipairs(rule_elements) do
        local converted, why = rule(rule_element, aliases)
        if converted then
          table.insert(slot, converted)
        else
          skip(('Slot %d rule %d'):format(slot_index, rule_index), why)
        end
      end
      if #slot > 0 then
        table.insert(raw.slots, slot)
      end
    end
  end
  return raw, skipped
end

return M
