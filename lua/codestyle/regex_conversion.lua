-- Regex Conversion (ADR-0011, ADR-0018): a Java regex, as PhpStorm stores
-- marker tags and Arrangement names, becomes a Vim regex in magic mode, the
-- syntax that the Core stores and `vim.regex` runs.
--
-- NAMED SEAM (#50 module 9): it converts the basic subset (plain text,
-- escapes, character classes, quantifiers, groups, alternation, and `(?i)` at
-- the start) and reports anything else as "cannot convert". The PHP map
-- settles the edge cases and records them in ADR-0011. A test pins this
-- subset, so each change shows as a diff. The Scheme XML import and
-- `codestyle.testing` both use it.

local M = {}

--- The characters that are special in a Vim magic regex, so a literal one is escaped.
local VIM_SPECIAL =
  { ['\\'] = true, ['^'] = true, ['$'] = true, ['.'] = true, ['*'] = true, ['['] = true, ['~'] = true }

--- Java escapes that are the same in Vim, outside a character class.
local SAME_ESCAPES =
  { d = true, D = true, w = true, W = true, s = true, S = true, t = true, n = true, r = true, e = true }

--- Java class escapes and their members inside a Vim collection.
local CLASS_SETS = { d = '0-9', w = '0-9A-Za-z_', s = ' \\t\\r\\n\\d11\\d12' }

---@param char string
---@return string
local function literal(char)
  return VIM_SPECIAL[char] and '\\' .. char or char
end

--- A Java regex as a Vim regex (magic mode), or nil and why it cannot be converted.
---@param pattern string
---@return string?
---@return string?
function M.from_java(pattern)
  local out = {} ---@type string[]
  local i = 1
  local depth = 0
  -- True where a Vim `^` is an anchor and a quantifier would have nothing to repeat.
  local branch_start = true

  local function fail(what)
    error({ reason = 'cannot convert ' .. what }, 0)
  end

  local function emit(text, starts_branch)
    table.insert(out, text)
    branch_start = starts_branch or false
  end

  --- A lazy or possessive suffix after a quantifier.
  local function check_suffix()
    local next_char = pattern:sub(i, i)
    if next_char == '?' or next_char == '+' then
      fail('a lazy or possessive quantifier')
    end
  end

  ---@param hex_length integer
  ---@return string
  local function hex(hex_length)
    local digits = pattern:sub(i + 2, i + 1 + hex_length)
    if not digits:match(('^' .. ('%x'):rep(hex_length) .. '$')) then
      fail('\\' .. pattern:sub(i + 1, i + 1) .. ' without ' .. hex_length .. ' hex digits')
    end
    i = i + 2 + hex_length
    return digits
  end

  local function class()
    local parts = { '[' }
    i = i + 1
    if pattern:sub(i, i) == '^' then
      table.insert(parts, '^')
      i = i + 1
    end
    local empty = true
    while true do
      local char = pattern:sub(i, i)
      if char == '' then
        fail('an unclosed [')
      elseif char == ']' then
        if empty then
          fail('an empty character class')
        end
        i = i + 1
        break
      elseif char == '[' then
        fail('a nested character class')
      elseif pattern:sub(i, i + 1) == '&&' then
        fail('a class intersection')
      elseif char == '\\' then
        local escaped = pattern:sub(i + 1, i + 1)
        if CLASS_SETS[escaped] then
          table.insert(parts, CLASS_SETS[escaped])
          i = i + 2
        elseif escaped == 't' or escaped == 'n' or escaped == 'r' or escaped == 'e' then
          table.insert(parts, '\\' .. escaped)
          i = i + 2
        elseif escaped == 'x' then
          table.insert(parts, '\\x' .. hex(2))
        elseif escaped == 'u' then
          table.insert(parts, '\\u' .. hex(4))
        elseif escaped == '' then
          fail('a trailing \\')
        elseif escaped:match('%w') then
          fail('\\' .. escaped .. ' in a character class')
        else
          local special = escaped == '^' or escaped == '-' or escaped == ']' or escaped == '\\'
          table.insert(parts, special and '\\' .. escaped or escaped)
          i = i + 2
        end
      else
        table.insert(parts, char)
        i = i + 1
      end
      empty = false
    end
    table.insert(parts, ']')
    emit(table.concat(parts))
  end

  local function escape()
    local escaped = pattern:sub(i + 1, i + 1)
    if escaped == '' then
      fail('a trailing \\')
    elseif SAME_ESCAPES[escaped] then
      emit('\\' .. escaped)
      i = i + 2
    elseif escaped == 'f' then
      emit('\\%x0c')
      i = i + 2
    elseif escaped == 'a' then
      emit('\\%x07')
      i = i + 2
    elseif escaped == 'x' then
      emit('\\%x' .. hex(2))
    elseif escaped == 'u' then
      emit('\\%u' .. hex(4))
    elseif escaped == 'Q' then
      local stop = pattern:find('\\E', i + 2, true)
      local quoted = pattern:sub(i + 2, stop and stop - 1 or #pattern)
      emit((quoted:gsub('.', literal)))
      i = stop and stop + 2 or #pattern + 1
    elseif escaped:match('%w') then
      fail('\\' .. escaped)
    else
      emit(literal(escaped))
      i = i + 2
    end
  end

  local ok, failure = pcall(function()
    if pattern:sub(1, 4) == '(?i)' then
      emit('\\c', true)
      i = 5
    end
    while i <= #pattern do
      local char = pattern:sub(i, i)
      if char == '(' then
        local head = pattern:sub(i, i + 2)
        if head == '(?:' then
          emit('\\%(', true)
          i = i + 3
        elseif head == '(?i' then
          fail('(?i) after the start')
        elseif pattern:sub(i + 1, i + 1) == '?' then
          fail(head)
        else
          emit('\\(', true)
          i = i + 1
        end
        depth = depth + 1
      elseif char == ')' then
        if depth == 0 then
          fail('an unmatched )')
        end
        depth = depth - 1
        emit('\\)')
        i = i + 1
      elseif char == '|' then
        emit('\\|', true)
        i = i + 1
      elseif char == '^' then
        if not branch_start then
          fail('^ inside a branch')
        end
        emit('^', true)
        i = i + 1
      elseif char == '$' then
        local after = pattern:sub(i + 1, i + 1)
        if not (after == '' or after == '|' or after == ')') then
          fail('$ inside a branch')
        end
        emit('$')
        i = i + 1
      elseif char == '*' or char == '+' or char == '?' then
        if branch_start then
          fail('a quantifier with nothing to repeat')
        end
        i = i + 1
        check_suffix()
        emit(({ ['*'] = '*', ['+'] = '\\+', ['?'] = '\\=' })[char])
      elseif char == '{' then
        local bounds = pattern:match('^{(%d+,?%d*)}', i)
        if not bounds then
          fail('an unclosed {')
        end
        if branch_start then
          fail('a quantifier with nothing to repeat')
        end
        i = i + #bounds + 2
        check_suffix()
        emit('\\{' .. bounds .. '}')
      elseif char == '.' then
        emit('.')
        i = i + 1
      elseif char == '[' then
        class()
      elseif char == '\\' then
        escape()
      else
        emit(literal(char))
        i = i + 1
      end
    end
    if depth > 0 then
      fail('an unclosed (')
    end
  end)
  if not ok then
    if type(failure) ~= 'table' then
      error(failure, 0)
    end
    return nil, failure.reason
  end
  return table.concat(out)
end

return M
