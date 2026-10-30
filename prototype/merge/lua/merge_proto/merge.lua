-- PROTOTYPE (throwaway): the Core's merge of a host block tree (PHP, Twig) with the block tree of a
-- combined injection (HTML). It ports the idea of IntelliJ's TemplateFormatUtil.mergeBlocks:
--   * markup (the embedded tree) is primary: its blocks are never dissolved;
--   * at each markup level, the host leaves that sit directly between the markup children span a range R,
--     and the topmost host blocks that fit inside R join that level;
--   * a block that contains blocks of the other tree takes them in as children;
--   * a host block that crosses a markup block is dissolved: its children take its place;
--   * a markup leaf that contains host blocks absorbs them (the leaf keeps its text).
local B = require('merge_proto.blocks')

local M = {}

local function sort_by_start(list)
  table.sort(list, function(a, b) return a.s < b.s or (a.s == b.s and a.e > b.e) end)
  return list
end

--- Topmost host blocks whose range fits inside [s, e). Walks the host tree as the Language Plugin built it
--- (`own`), not as the merge has rearranged it so far.
--- `split` gets each host block that had to be split because it reaches past [s, e).
local function topmost_in(block, s, e, out, split)
  if block.e <= s or block.s >= e then return out end
  if block.s >= s and block.e <= e then
    out[#out + 1] = block
  elseif block.own then
    split(block)
    for _, c in ipairs(block.own) do topmost_in(c, s, e, out, split) end
  end
  return out
end

local Merger = {}
Merger.__index = Merger

function M.new(host_root)
  local function keep(b)
    if not B.is_leaf(b) then
      b.own = vim.list_extend({}, b.children)
      for _, c in ipairs(b.children) do keep(c) end
    end
  end
  keep(host_root)
  return setmetatable({ host_root = host_root, host_leaves = B.leaves(host_root), log = {} }, Merger)
end

--- Joins markup blocks C and host blocks H into one sibling list. Each host block that crosses a markup
--- block is dissolved. Blocks that contain blocks of the other list take them in (`inner`), except that
--- host blocks inside a markup block are dropped here: the markup block finds them again at its own level.
function Merger:join(C, H)
  H = vim.list_extend({}, H)
  local i = 1
  while i <= #H do
    local h = H[i]
    local crossed
    for _, c in ipairs(C) do
      if B.crosses(h, c) then crossed = c break end
    end
    if crossed and not B.is_leaf(h) then
      self.log[#self.log + 1] = { block = h, crossed = crossed }
      table.remove(H, i)
      for k, child in ipairs(h.own) do table.insert(H, i + k - 1, child) end
    else
      if crossed then
        -- A host leaf cannot be dissolved. Real parses do not produce this; keep the markup block's text.
        crossed.readonly = true
      end
      i = i + 1
    end
  end
  local out, taken = {}, {}
  for _, h in ipairs(H) do
    local dropped = false
    for _, c in ipairs(C) do
      if B.contains(c, h) and not B.contains(h, c) then dropped = true break end
    end
    if not dropped then
      for _, c in ipairs(C) do
        if not taken[c] and B.contains(h, c) then
          h.inner = h.inner or {}
          h.inner[#h.inner + 1] = c
          taken[c] = true
        end
      end
      out[#out + 1] = h
    end
  end
  for _, c in ipairs(C) do
    if not taken[c] then out[#out + 1] = c end
  end
  return sort_by_start(out)
end

--- Host leaves inside markup block `m` that are not inside one of its markup children.
function Merger:host_leaves_between(m)
  local found = {}
  for _, l in ipairs(self.host_leaves) do
    if l.s >= m.s and l.e <= m.e then
      local inside = false
      for _, c in ipairs(m.children) do
        if B.contains(c, l) then inside = true break end
      end
      if not inside then found[#found + 1] = l end
    end
  end
  return found
end

function Merger:markup(m)
  if B.is_leaf(m) then return end
  local between = self:host_leaves_between(m)
  if #between > 0 then
    local H = topmost_in(self.host_root, between[1].s, between[#between].e, {}, function(h)
      -- A host block that is split here and is not around `m` crosses it: like a dissolve.
      if B.crosses(h, m) then self.log[#self.log + 1] = { block = h, crossed = m } end
    end)
    m.children = self:join(m.children, H)
  end
  self:recurse(m)
end

function Merger:host(h)
  if h.inner then
    local inner = h.inner
    h.inner = nil
    if not B.is_leaf(h) then
      -- Inside a host block the roles stay the same: markup is primary, host children that cross it dissolve.
      h.children = self:join(inner, h.children)
    end
  end
  self:recurse(h)
end

function Merger:recurse(b)
  if B.is_leaf(b) then return end
  for _, c in ipairs(b.children) do
    if c.embedded then self:markup(c) else self:host(c) end
  end
end

--- Merges the host tree with the markup tree. Returns the merged root and the log of dissolved host blocks.
function M.merge(host_root, markup_root)
  if not markup_root then return host_root, {} end
  local m = M.new(host_root)
  local function mark(b)
    b.embedded = true
    if b.children then for _, c in ipairs(b.children) do mark(c) end end
  end
  mark(markup_root)
  -- The file level: the markup root (document) spans the whole file, like IntelliJ's XmlDocument, so host
  -- code before the first or after the last HTML is at the document level too.
  local file_end = math.max(host_root.e, markup_root.e)
  markup_root.s, markup_root.e = 0, file_end
  local root = { lang = host_root.lang, type = 'file', s = 0, e = file_end, children = { markup_root } }
  m:markup(markup_root)
  return root, m.log
end

function M.set_parents(b, parent)
  b.parent = parent
  if b.children and not b.readonly then
    for _, c in ipairs(b.children) do M.set_parents(c, b) end
  end
end

return M
