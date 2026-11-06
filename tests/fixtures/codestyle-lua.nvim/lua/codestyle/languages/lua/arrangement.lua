-- The fake `lua` Arrangement module (ADR-0011): the entries are the members of
-- the module table, the identifier that the chunk's last `return` gives.
-- `M.x = 1` is a `field`, `function M.x()` and `M.x = function` a `function`,
-- `function M:x()` a `method`. Doc comments (`---`) right above a member and
-- a comment after it on its last line travel with it; other comments stay.
-- Keep-Together links: `get_x` with `set_x`, calls of `M.x()`, `M:x()` and
-- `self:x()`, and the members of each parent that the LSP names.

local arrangement = require('codestyle.arrangement')
local entry = require('codestyle.arrangement_entry')

local M = {}

---@param node TSNode
---@param source string
---@return string
local function text(node, source)
  return vim.treesitter.get_node_text(node, source)
end

--- The member that a statement declares: its type and name.
---@param node TSNode
---@param module string
---@param source string
---@return string? type
---@return string? name
local function member(node, module, source)
  local name, value
  if node:type() == 'function_declaration' then
    name = node:field('name')[1]
  elseif node:type() == 'assignment_statement' then
    local variables = node:named_child(0)
    local values = node:named_child(1)
    if variables and variables:named_child_count() == 1 then
      name = variables:named_child(0)
      value = values and values:named_child(0)
    end
  end
  if not name then
    return nil
  end
  local kind = name:type()
  if kind ~= 'dot_index_expression' and kind ~= 'method_index_expression' then
    return nil
  end
  local table_node = name:field('table')[1]
  if not table_node or table_node:type() ~= 'identifier' or text(table_node, source) ~= module then
    return nil
  end
  local key = name:field(kind == 'dot_index_expression' and 'field' or 'method')[1]
  if kind == 'method_index_expression' then
    return 'method', text(key, source)
  end
  if node:type() == 'function_declaration' or (value and value:type() == 'function_definition') then
    return 'function', text(key, source)
  end
  return 'field', text(key, source)
end

--- The names of the members that a member calls, in the order of the calls.
---@param node TSNode
---@param module string
---@param source string
---@return string[]
local function calls(node, module, source)
  local names = {}
  local function visit(current)
    if current:type() == 'function_call' then
      local name = current:field('name')[1]
      local table_node = name and name:field('table')[1]
      local owner = table_node and table_node:type() == 'identifier' and text(table_node, source)
      if owner == module or (owner == 'self' and name:type() == 'method_index_expression') then
        local key = name:field(name:type() == 'dot_index_expression' and 'field' or 'method')[1]
        if key then
          table.insert(names, text(key, source))
        end
      end
    end
    for child in current:iter_children() do
      visit(child)
    end
  end
  visit(node)
  return names
end

--- The parents of the module that the LSP names, nearest first, each with the
--- names of its members.
---@param ctx codestyle.ArrangementContext
---@param module string
---@return { name: string, members: table<string, true> }[]
local function parents(ctx, module)
  local zero = { start = { line = 0, character = 0 }, ['end'] = { line = 0, character = 0 } }
  local supertypes = ctx.lsp('typeHierarchy/supertypes', {
    item = { name = module, kind = 5, uri = 'file:///module.lua', range = zero, selectionRange = zero },
  }) or {}
  local result = {}
  for _, item in ipairs(supertypes) do
    local symbols = ctx.lsp('textDocument/documentSymbol', { textDocument = { uri = item.uri } }) or {}
    local members = {}
    for _, symbol in ipairs(symbols) do
      members[symbol.name] = true
    end
    table.insert(result, { name = item.name, members = members })
  end
  return result
end

---@param ctx codestyle.ArrangementContext
---@return codestyle.ArrangementEntry[]
function M.entries(ctx)
  local root, source = ctx.root, ctx.source
  local last
  for child in root:iter_children() do
    if child:named() then
      last = child
    end
  end
  local returned = last and last:type() == 'return_statement' and last:named_child(0)
  local identifier = returned and returned:named_child(0)
  if not identifier or identifier:type() ~= 'identifier' then
    return {}
  end
  local module = text(identifier, source)

  local entries, by_name, nodes = {}, {}, {}
  local children = {}
  for child in root:iter_children() do
    if child:named() then
      table.insert(children, child)
    end
  end
  for index, child in ipairs(children) do
    local type, name = member(child, module, source)
    if type and name then
      local start_row, start_col, end_row, end_col = child:range()
      -- Doc comments right above it travel with it.
      local above = index - 1
      while above >= 1 and children[above]:type() == 'comment' do
        local comment = children[above]
        local comment_start, comment_col, comment_end = comment:range()
        if comment_end ~= start_row - 1 or not vim.startswith(text(comment, source), '---') then
          break
        end
        start_row, start_col = comment_start, comment_col
        above = above - 1
      end
      -- A comment after it on its last line travels with it.
      local after = children[index + 1]
      if after and after:type() == 'comment' and after:range() == end_row then
        local _, _, after_end_row, after_end_col = after:range()
        end_row, end_col = after_end_row, after_end_col
      end
      local modifiers = {}
      if vim.startswith(name, '__') then
        table.insert(modifiers, 'metamethod')
      elseif vim.startswith(name, '_') then
        table.insert(modifiers, 'private')
      end
      local new = entry.new({
        range = { start_row, start_col, end_row, end_col },
        types = { type },
        modifiers = modifiers,
        name = name,
        namespace = module,
      })
      table.insert(entries, new)
      by_name[name] = by_name[name] or new
      nodes[new] = child
    end
  end

  for _, field in ipairs(entries) do
    if field.types[1] == 'field' then
      local getter, setter = by_name['get_' .. field.name], by_name['set_' .. field.name]
      if getter and setter and getter.types[1] ~= 'field' and setter.types[1] ~= 'field' then
        getter.links.getters_setters = { setter }
      end
    end
  end
  for _, caller in ipairs(entries) do
    if caller.types[1] ~= 'field' then
      local callees = {}
      for _, name in ipairs(calls(nodes[caller], module, source)) do
        if by_name[name] and by_name[name].types[1] ~= 'field' then
          table.insert(callees, by_name[name])
        end
      end
      caller.links.dependent_methods = callees
    end
  end

  -- Only an Arrangement that uses them asks the LSP for the parents.
  if arrangement.uses(ctx.arrangement, 'overridden') or arrangement.uses(ctx.arrangement, 'overridden_methods') then
    local found = parents(ctx, module)
    local groups = {}
    for _, candidate in ipairs(entries) do
      if candidate.types[1] ~= 'field' then
        for _, parent in ipairs(found) do
          if parent.members[candidate.name] then
            table.insert(candidate.modifiers, 'overridden')
            groups[parent.name] = groups[parent.name] or {}
            table.insert(groups[parent.name], candidate)
            break
          end
        end
      end
    end
    for _, group in pairs(groups) do
      group[1].links.overridden_methods = vim.list_slice(group, 2)
    end
  end
  return entries
end

--- One blank line next to a function or method, none between two fields.
---@param previous codestyle.ArrangementEntry
---@param current codestyle.ArrangementEntry
---@return integer
function M.blank_lines(previous, current)
  return (previous.types[1] == 'field' and current.types[1] == 'field') and 0 or 1
end

return M
