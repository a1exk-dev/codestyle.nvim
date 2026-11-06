-- `SpacingBuilder` for Language Plugins (ADR-0007): a port of IntelliJ's
-- `com.intellij.formatting.SpacingBuilder`. A plugin lists rules once, at
-- load time, and gives `rules()` as (part of) its `formatter.rules`: one
-- `codestyle.Rule` per condition, in order, each naming the Block types it
-- needs, so the Core skips only the rules whose node types the parser lacks.
-- The first rule that matches the parent and the two children of a Gap gives
-- its Spacing.
--
--   local sb = require('codestyle.spacing_builder').new({ keep_blank_lines = 2 })
--     .around_inside('=', 'assignment_statement').space_if(function(values) return values.spaces.around end)
--     .after(',').spaces(1)
--   formatter.rules = sb.rules()
--
-- Upstream reads Option values when the builder is made. A plugin keeps no
-- state between runs (ADR-0007), so here every count and condition is a value
-- or a function of the Option values, read when a rule is called.
-- Not ported: `parentDependentLFSpacing`.

local spacing = require('codestyle.spacing')

--- A Block type, or a list of them (upstream's `TokenSet`).
---@alias codestyle.BlockTypes string|string[]

--- A value, or a function of the Option values that returns it.
---@alias codestyle.ValueOf any|fun(values: codestyle.Values): any

---@class codestyle.SpacingBuilderOpts
---@field keep_line_breaks? codestyle.ValueOf boolean, default true
---@field keep_blank_lines? codestyle.ValueOf integer for rules in code, default nil (keep all)
---@field keep_blank_lines_in_declarations? codestyle.ValueOf integer for `blank_lines`, default nil (keep all)

---@class codestyle.SpacingBuilder
---@field after fun(types: codestyle.BlockTypes): codestyle.SpacingRuleBuilder
---@field after_inside fun(types: codestyle.BlockTypes, parent: codestyle.BlockTypes): codestyle.SpacingRuleBuilder
---@field before fun(types: codestyle.BlockTypes): codestyle.SpacingRuleBuilder
---@field before_inside fun(types: codestyle.BlockTypes, parent: codestyle.BlockTypes): codestyle.SpacingRuleBuilder
---@field around fun(types: codestyle.BlockTypes): codestyle.SpacingRuleBuilder
---@field around_inside fun(types: codestyle.BlockTypes, parent: codestyle.BlockTypes): codestyle.SpacingRuleBuilder
---@field between fun(left: codestyle.BlockTypes, right: codestyle.BlockTypes): codestyle.SpacingRuleBuilder
---@field between_inside fun(left: codestyle.BlockTypes, right: codestyle.BlockTypes, parent: codestyle.BlockTypes): codestyle.SpacingRuleBuilder
---@field within_pair fun(first: codestyle.BlockTypes, second: codestyle.BlockTypes): codestyle.SpacingRuleBuilder
---@field within_pair_inside fun(first: codestyle.BlockTypes, second: codestyle.BlockTypes, parent: codestyle.BlockTypes): codestyle.SpacingRuleBuilder
---@field append fun(other: codestyle.SpacingBuilder): codestyle.SpacingBuilder adds the other builder's rules after these
---@field rules fun(): codestyle.Rule[] one rule per condition, in order, for `formatter.rules`

--- Ends a rule: what the Gaps that the rule matches get.
---@class codestyle.SpacingRuleBuilder
---@field spaces fun(count: codestyle.ValueOf): codestyle.SpacingBuilder
---@field none fun(): codestyle.SpacingBuilder
---@field space_if fun(option: codestyle.ValueOf): codestyle.SpacingBuilder one space when true, none when false
---@field spacing fun(min_spaces: codestyle.ValueOf, max_spaces: codestyle.ValueOf, min_line_feeds: codestyle.ValueOf, keep_line_breaks: codestyle.ValueOf, keep_blank_lines: codestyle.ValueOf): codestyle.SpacingBuilder
---@field blank_lines fun(count: codestyle.ValueOf): codestyle.SpacingBuilder at least `count` blank lines
---@field line_break_in_code fun(): codestyle.SpacingBuilder
---@field line_break_in_code_if fun(option: codestyle.ValueOf): codestyle.SpacingBuilder when false, the rule does not match
---@field line_break_or_force_space fun(line_break: codestyle.ValueOf, space: codestyle.ValueOf): codestyle.SpacingBuilder

local M = {}

---@param types? codestyle.BlockTypes
---@return table<string, true>?
local function type_set(types)
  if types == nil then
    return nil
  end
  local set = {}
  for _, name in ipairs(type(types) == 'table' and types or { types }) do
    set[name] = true
  end
  return set
end

---@param value codestyle.ValueOf
---@param values codestyle.Values
---@return any
local function read(value, values)
  if type(value) == 'function' then
    return value(values)
  end
  return value
end

--- One condition of a rule: the parent, left and right types, nil for any.
---@param parent? codestyle.BlockTypes
---@param left? codestyle.BlockTypes
---@param right? codestyle.BlockTypes
---@return table
local function condition(parent, left, right)
  local nodes = {}
  for _, types in ipairs({ parent or {}, left or {}, right or {} }) do
    vim.list_extend(nodes, type(types) == 'table' and types or { types })
  end
  return { parent = type_set(parent), left = type_set(left), right = type_set(right), nodes = nodes }
end

---@param set? table<string, true>
---@param block codestyle.Block
---@return boolean
local function contains(set, block)
  return set == nil or set[block.type] == true
end

---@param opts? codestyle.SpacingBuilderOpts
---@return codestyle.SpacingBuilder
function M.new(opts)
  opts = opts or {}
  local rules = {} ---@type codestyle.Rule[]
  ---@diagnostic disable-next-line: missing-fields
  local builder = {} ---@type codestyle.SpacingBuilder

  ---@param values codestyle.Values
  ---@return boolean
  local function keep_line_breaks(values)
    return read(opts.keep_line_breaks, values) ~= false
  end

  ---@param conditions table[]
  ---@return codestyle.SpacingRuleBuilder
  local function rule_builder(conditions)
    ---@diagnostic disable-next-line: missing-fields
    local rule = {} ---@type codestyle.SpacingRuleBuilder

    ---@param make fun(values: codestyle.Values): codestyle.Spacing?
    ---@return codestyle.SpacingBuilder
    local function add(make)
      for _, each in ipairs(conditions) do
        table.insert(rules, {
          nodes = each.nodes,
          spacing = function(parent, left, right, values)
            if contains(each.parent, parent) and contains(each.left, left) and contains(each.right, right) then
              return make(values)
            end
          end,
        })
      end
      return builder
    end

    function rule.spacing(min_spaces, max_spaces, min_line_feeds, keep_breaks, keep_blank_lines)
      return add(function(values)
        return spacing.create(
          read(min_spaces, values),
          read(max_spaces, values),
          read(min_line_feeds, values),
          read(keep_breaks, values),
          read(keep_blank_lines, values)
        )
      end)
    end

    function rule.spaces(count)
      return add(function(values)
        local n = read(count, values)
        return spacing.create(n, n, 0, keep_line_breaks(values), read(opts.keep_blank_lines, values))
      end)
    end

    function rule.none()
      return rule.spaces(0)
    end

    function rule.space_if(option)
      return rule.spaces(function(values)
        return read(option, values) and 1 or 0
      end)
    end

    function rule.blank_lines(count)
      return add(function(values)
        local line_feeds = read(count, values) + 1
        return spacing.create(
          0,
          0,
          line_feeds,
          keep_line_breaks(values),
          read(opts.keep_blank_lines_in_declarations, values)
        )
      end)
    end

    ---@param values codestyle.Values
    ---@return codestyle.Spacing
    local function line_break(values)
      return spacing.create(1, 0, 1, keep_line_breaks(values), read(opts.keep_blank_lines, values))
    end

    function rule.line_break_in_code()
      return add(line_break)
    end

    function rule.line_break_in_code_if(option)
      return add(function(values)
        return read(option, values) and line_break(values) or nil
      end)
    end

    function rule.line_break_or_force_space(line_break_option, space_option)
      return add(function(values)
        if read(line_break_option, values) then
          return line_break(values)
        end
        local count = read(space_option, values) and 1 or 0
        return spacing.create(count, count, 0, false, 0)
      end)
    end

    return rule
  end

  function builder.after(types)
    return rule_builder({ condition(nil, types, nil) })
  end
  function builder.after_inside(types, parent)
    return rule_builder({ condition(parent, types, nil) })
  end
  function builder.before(types)
    return rule_builder({ condition(nil, nil, types) })
  end
  function builder.before_inside(types, parent)
    return rule_builder({ condition(parent, nil, types) })
  end
  function builder.around(types)
    return rule_builder({ condition(nil, nil, types), condition(nil, types, nil) })
  end
  function builder.around_inside(types, parent)
    return rule_builder({ condition(parent, nil, types), condition(parent, types, nil) })
  end
  function builder.between(left, right)
    return rule_builder({ condition(nil, left, right) })
  end
  function builder.between_inside(left, right, parent)
    return rule_builder({ condition(parent, left, right) })
  end
  function builder.within_pair(first, second)
    return rule_builder({ condition(nil, first, nil), condition(nil, nil, second) })
  end
  function builder.within_pair_inside(first, second, parent)
    return rule_builder({ condition(parent, first, nil), condition(parent, nil, second) })
  end

  function builder.rules()
    return rules
  end

  function builder.append(other)
    vim.list_extend(rules, other.rules())
    return builder
  end

  return builder
end

return M
