-- PROTOTYPE (throwaway): a toy HTML Language Plugin. Only indent rules: tags, text words, attribute alignment.
local B = require('merge_proto.blocks')

local P = { id = 'html', parser = 'html' }

local VOID = {}
for _, t in ipairs({ 'area', 'base', 'br', 'col', 'embed', 'hr', 'img', 'input', 'link', 'meta', 'source', 'track', 'wbr' }) do VOID[t] = true end
local OPTIONAL_END = {}
for _, t in ipairs({ 'html', 'head', 'body', 'p', 'li', 'dt', 'dd', 'option', 'optgroup', 'tr', 'td', 'th', 'thead', 'tbody', 'tfoot', 'colgroup', 'caption', 'rp', 'rt' }) do OPTIONAL_END[t] = true end

local function words(src, s, e, included, out)
  -- Split text into word leaves, but only inside the ranges the HTML parser saw: in a combined injection
  -- one HTML text node can span host code that the parser skipped.
  for _, r in ipairs(included) do
    local a, z = math.max(s, r[3]), math.min(e, r[6])
    if a < z then
      local piece = src:sub(a + 1, z)
      for ws, we in piece:gmatch('()%S+()') do
        out[#out + 1] = { lang = 'html', type = 'word', s = a + ws - 1, e = a + we - 1 }
      end
    end
  end
end

local function build(node, src, included)
  local t = node:type()
  local s, e = B.byte_range(node)
  if t == 'ERROR' or t == 'script_element' or t == 'style_element' then
    local l = B.leaf('html', t, src, s, e, { readonly = true })
    return l and { l } or {}
  end
  if t == 'text' then
    local out = {}
    words(src, s, e, included, out)
    return out
  end
  if t == 'start_tag' or t == 'self_closing_tag' then
    local kids, head_s, head_e = {}, nil, nil
    for c in node:iter_children() do
      local ct = c:type()
      local cs, ce = B.byte_range(c)
      if ct == '<' or ct == 'tag_name' then
        head_s, head_e = head_s or cs, ce
      elseif ct == 'attribute' then
        kids[#kids + 1] = B.leaf('html', 'attribute', src, cs, ce)
      else
        kids[#kids + 1] = B.leaf('html', ct, src, cs, ce)
      end
    end
    table.insert(kids, 1, B.leaf('html', 'tag_head', src, head_s, head_e))
    return { B.composite('html', t, kids) }
  end
  if node:child_count() == 0 or t == 'end_tag' or t == 'doctype' or t == 'comment' or t == 'entity' or t == 'erroneous_end_tag' then
    local l = B.leaf('html', t, src, s, e)
    return l and { l } or {}
  end
  local children = {}
  for c in node:iter_children() do vim.list_extend(children, build(c, src, included)) end
  local extra = {}
  if t == 'element' then
    local st = node:child(0)
    local name = st and st:named_child(0)
    if name and name:type() == 'tag_name' then extra.tag = vim.treesitter.get_node_text(name, src):lower() end
  end
  if t == 'element' and extra.tag and not VOID[extra.tag] and not OPTIONAL_END[extra.tag] then
    local closed = false
    for c in node:iter_children() do
      if c:type() == 'end_tag' then closed = true end
    end
    -- tree-sitter-html closes an element at the end of its parent without an error. IntelliJ reports
    -- "element is not closed", and its template formatter then keeps the text of the fragment.
    if not closed then
      extra.readonly = true
      extra.error = 'unclosed <' .. extra.tag .. '>'
    end
  end
  local b = B.composite('html', t, children, extra)
  return b and { b } or {}
end

function P.build(tree_root, src, included)
  local children = {}
  for c in tree_root:iter_children() do vim.list_extend(children, build(c, src, included)) end
  return B.composite('html', 'document', children)
end

function P.indent_options() return 'html' end

function P.child_indent(parent, child, style)
  local t = parent.type
  if t == 'document' then return 'none' end
  if t == 'start_tag' or t == 'self_closing_tag' then
    if child.type == 'attribute' then
      local first
      for _, c in ipairs(parent.children) do
        if c.type == 'attribute' then first = c break end
      end
      if style.align_attributes and first ~= child then return { align = first } end
      return 'continuation'
    end
    return 'none'
  end
  if t == 'element' then
    if child.type == 'start_tag' or child.type == 'end_tag' or child.type == 'self_closing_tag' then return 'none' end
    if parent.tag and vim.tbl_contains(style.do_not_indent_children_of, parent.tag) then return 'none' end
    return 'normal' -- content, including blocks of the host language
  end
  return 'none'
end

return P
