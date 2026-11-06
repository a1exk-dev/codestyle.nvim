-- The template merge (ADR-0005): a port of IntelliJ's
-- `TemplateFormatUtil.mergeBlocks` (Apache-2.0), after the merge prototype
-- (#19). It merges the host's Block tree, which has holes where the template
-- layer is, with the Block tree of the template layer (the markup), into one
-- tree. Markup is primary: a markup Block is never split.
--
-- - At each markup level, the host leaves that lie directly between the
--   markup children span a range, and the topmost host Blocks that fit in it
--   join that level.
-- - A Block that holds Blocks of the other tree takes them in as children.
-- - A host Block that crosses a markup Block is split into its children.
-- - The markup root spans the whole file, so the host root joins only when
--   its leaves span the whole level.

local M = {}

---@param row_a integer
---@param col_a integer
---@param row_b integer
---@param col_b integer
---@return boolean
local function before(row_a, col_a, row_b, col_b)
  return row_a < row_b or (row_a == row_b and col_a < col_b)
end

--- `a` holds `b`.
---@param a codestyle.Block
---@param b codestyle.Block
---@return boolean
local function contains(a, b)
  local ra, rb = a.range, b.range
  return not before(rb[1], rb[2], ra[1], ra[2]) and not before(ra[3], ra[4], rb[3], rb[4])
end

---@param a codestyle.Block
---@param b codestyle.Block
---@return boolean
local function overlaps(a, b)
  local ra, rb = a.range, b.range
  return before(ra[1], ra[2], rb[3], rb[4]) and before(rb[1], rb[2], ra[3], ra[4])
end

---@param a codestyle.Block
---@param b codestyle.Block
---@return boolean
local function crosses(a, b)
  return overlaps(a, b) and not contains(a, b) and not contains(b, a)
end

---@param list codestyle.Block[]
---@return codestyle.Block[]
local function sort_by_start(list)
  table.sort(list, function(a, b)
    local ra, rb = a.range, b.range
    if ra[1] ~= rb[1] or ra[2] ~= rb[2] then
      return before(ra[1], ra[2], rb[1], rb[2])
    end
    return before(rb[3], rb[4], ra[3], ra[4])
  end)
  return list
end

---@param root codestyle.Block
---@param leaves? codestyle.Block[]
---@return codestyle.Block[]
local function leaves_of(root, leaves)
  leaves = leaves or {}
  if #root.children == 0 then
    table.insert(leaves, root)
  else
    for _, child in ipairs(root.children) do
      leaves_of(child, leaves)
    end
  end
  return leaves
end

--- Merges the host tree with the markup tree. The markup root gets the range
--- of the whole file and is the root of the merged tree.
---@param host_root codestyle.Block
---@param markup_root codestyle.Block
---@param file_range integer[]
---@return codestyle.Block
function M.merge(host_root, markup_root, file_range)
  local own = {} ---@type table<codestyle.Block, codestyle.Block[]> the children that the host plugin built
  local inner = {} ---@type table<codestyle.Block, codestyle.Block[]> markup Blocks that a host Block takes in
  local markup_blocks = {} ---@type table<codestyle.Block, true>

  ---@param block codestyle.Block
  local function keep(block)
    own[block] = vim.list_extend({}, block.children)
    for _, child in ipairs(block.children) do
      keep(child)
    end
  end
  keep(host_root)

  ---@param block codestyle.Block
  local function mark(block)
    markup_blocks[block] = true
    for _, child in ipairs(block.children) do
      mark(child)
    end
  end
  mark(markup_root)

  -- A host tree of holes only has no leaves: the markup alone is the tree.
  local host_leaves = #host_root.children > 0 and leaves_of(host_root) or {}

  --- The topmost host Blocks, in the tree the host plugin built, that fit in `area`.
  ---@param block codestyle.Block
  ---@param area codestyle.Block
  ---@param found codestyle.Block[]
  ---@return codestyle.Block[]
  local function topmost_in(block, area, found)
    if not overlaps(block, area) then
      return found
    end
    if contains(area, block) then
      table.insert(found, block)
    else
      for _, child in ipairs(own[block]) do
        topmost_in(child, area, found)
      end
    end
    return found
  end

  --- Joins markup Blocks and host Blocks into one sibling list.
  ---@param markup codestyle.Block[]
  ---@param host codestyle.Block[]
  ---@return codestyle.Block[]
  local function join(markup, host)
    host = vim.list_extend({}, host)
    local index = 1
    while index <= #host do
      local candidate = host[index]
      local crossed = false
      for _, block in ipairs(markup) do
        crossed = crossed or crosses(candidate, block)
      end
      if crossed and #own[candidate] > 0 then
        -- Split: its children take its place.
        table.remove(host, index)
        for offset, child in ipairs(own[candidate]) do
          table.insert(host, index + offset - 1, child)
        end
      else
        index = index + 1
      end
    end
    local joined, taken = {}, {}
    for _, candidate in ipairs(host) do
      local dropped = false
      for _, block in ipairs(markup) do
        -- A host Block inside a markup Block joins at that Block's own level.
        dropped = dropped or (contains(block, candidate) and not contains(candidate, block))
      end
      if not dropped then
        for _, block in ipairs(markup) do
          if not taken[block] and contains(candidate, block) then
            inner[candidate] = inner[candidate] or {}
            table.insert(inner[candidate], block)
            taken[block] = true
          end
        end
        table.insert(joined, candidate)
      end
    end
    for _, block in ipairs(markup) do
      if not taken[block] then
        table.insert(joined, block)
      end
    end
    return sort_by_start(joined)
  end

  local visit

  ---@param block codestyle.Block
  local function visit_markup(block)
    if #block.children == 0 then
      return
    end
    local between = vim.tbl_filter(function(leaf)
      if not contains(block, leaf) then
        return false
      end
      for _, child in ipairs(block.children) do
        if contains(child, leaf) then
          return false
        end
      end
      return true
    end, host_leaves)
    if #between > 0 then
      local first, last = between[1].range, between[#between].range
      local area = { range = { first[1], first[2], last[3], last[4] }, children = {}, type = '' }
      block.children = join(block.children, topmost_in(host_root, area, {}))
    end
    visit(block)
  end

  ---@param block codestyle.Block
  local function visit_host(block)
    local taken = inner[block]
    if taken then
      inner[block] = nil
      if #block.children > 0 then
        block.children = join(taken, block.children)
      end
    end
    visit(block)
  end

  ---@param block codestyle.Block
  visit = function(block)
    for _, child in ipairs(block.children) do
      if markup_blocks[child] then
        visit_markup(child)
      else
        visit_host(child)
      end
    end
  end

  markup_root.range = file_range
  visit_markup(markup_root)
  return markup_root
end

return M
