-- PROTOTYPE (throwaway): the Core's indent pass over a merged block tree, plus gap ownership.
-- It only rewrites the indentation of lines. Spacing inside lines is left alone, but each gap still gets an
-- owner (the lowest block that contains both leaves) so the report can show which Language Plugin decides it.
--
-- Rules (IntelliJ's): an indent applies only to a block that starts a line. A block's indent kind
-- (none / normal / continuation / align) is chosen by its parent's Language Plugin, even when the child is of
-- another language. The columns of one kind come from one set of indent Options for the whole file, which the
-- host Language Plugin picks. The base of a child is the new indent of the line where its parent starts.
local B = require('merge_proto.blocks')

local M = {}

local function first_leaf(b)
  while not B.is_leaf(b) do b = b.children[1] end
  return b
end

local function lca(a, b)
  local seen = {}
  local x = a
  while x do seen[x] = true x = x.parent end
  x = b
  while x and not seen[x] do x = x.parent end
  return x
end

--- The outermost block that starts with this leaf.
local function line_block(leaf)
  local b = leaf
  while b.parent and first_leaf(b.parent) == leaf and b.parent.parent do b = b.parent end
  return b
end

local function readonly_ancestor(b)
  local x = b.parent
  while x do
    if x.readonly then return x end
    x = x.parent
  end
end

local function render(col, io)
  -- Without smart tabs, tabs fill every whole tab stop, also under an alignment (Research Corpus: twig indent_style).
  if not io.use_tab then return string.rep(' ', col) end
  local tabs = math.floor(col / io.tab_size)
  local rest = col - tabs * io.tab_size
  return string.rep('\t', tabs) .. string.rep(' ', rest)
end

local function display_width(s, tab_size)
  local w = 0
  for ch in s:gmatch('.') do
    if ch == '\t' then w = w + tab_size - (w % tab_size) else w = w + 1 end
  end
  return w
end

--- @param ctx { src: string, root: table, plugins: table<string, table>, styles: table, io: table }
--- @return string new_text, table lines  (one entry per line start: who decided its indent)
function M.run(ctx)
  local src, io = ctx.src, ctx.io
  local leaves = B.leaves(ctx.root)
  local out = {}
  local col = 0 -- display column at the end of `out`
  local line_indent = {} -- leaf -> new indent column of the line it is on
  local leaf_col = {} -- leaf -> new start column
  local cur_line_indent = 0
  local info = { lines = {}, gaps = {} }

  local function emit(s)
    out[#out + 1] = s
    local last_nl = s:match('.*()\n')
    if last_nl then col = display_width(s:sub(last_nl + 1), io.tab_size) else col = col + display_width(s, io.tab_size) end
  end

  local function size(kind, parent_base)
    if kind == 'none' then return parent_base end
    if kind == 'normal' then return parent_base + io.indent_size end
    if kind == 'continuation' then return parent_base + io.continuation_indent_size end
    error('unknown indent kind ' .. vim.inspect(kind))
  end

  local prev_end = 0
  for i, leaf in ipairs(leaves) do
    local gap = src:sub(prev_end + 1, leaf.s)
    local ro = readonly_ancestor(leaf)
    if i > 1 then
      local owner = lca(leaves[i - 1], leaf)
      info.gaps[#info.gaps + 1] = { left = leaves[i - 1], right = leaf, owner = owner, newline = gap:find('\n') ~= nil }
    end
    if i > 1 and gap:find('\n') and not ro then
      local head = gap:match('^(.*\n)')
      head = head:gsub('[ \t]+\n', '\n') -- blank lines carry no indent
      local L = line_block(leaf)
      local P = L.parent
      local plugin = ctx.plugins[P.lang]
      local kind = P.type == 'file' and 'none' or plugin.child_indent(P, L, ctx.styles[P.lang] or {})
      local base = line_indent[first_leaf(P)] or 0
      local new_col, text
      if type(kind) == 'table' and kind.align then
        new_col = leaf_col[first_leaf(kind.align)] or base
        text = render(new_col, io)
      elseif kind == 'keep' then
        text = gap:match('\n([^\n]*)$')
        new_col = display_width(text, io.tab_size)
      else
        new_col = size(kind, base)
        text = render(new_col, io)
      end
      emit(head)
      emit(text)
      cur_line_indent = new_col
      info.lines[#info.lines + 1] = { leaf = leaf, block = L, parent = P, kind = kind, col = new_col }
    else
      emit(gap)
      if i == 1 or gap:find('\n') then
        cur_line_indent = col
      end
    end
    leaf_col[leaf] = col
    line_indent[leaf] = cur_line_indent
    local text = src:sub(leaf.s + 1, leaf.e)
    emit(text)
    if text:find('\n') then
      cur_line_indent = display_width(text:match('\n([ \t]*)[^\n]*$'), io.tab_size)
    end
    prev_end = leaf.e
  end
  emit(src:sub(prev_end + 1))
  return table.concat(out), info
end

return M
