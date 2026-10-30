-- PROTOTYPE (throwaway): a toy Twig Language Plugin. The Twig grammar is flat: `{% if %}` and `{% endif %}`
-- are sibling nodes. So the builder pairs the tags itself into synthetic blocks, which is what gives the
-- HTML between them its indent.
local B = require('merge_proto.blocks')

local P = { id = 'twig', parser = 'twig' }

local OPENERS = {
  block = true, ['if'] = true, ['for'] = true, macro = true, embed = true, apply = true, with = true,
  verbatim = true, autoescape = true, filter = true, sandbox = true, spaceless = true,
}
local MIDDLES = { ['else'] = true, ['elseif'] = true }
local ATOMIC = { string = true, comment = true, number = true }

local function tag_name(node, src)
  -- The grammar has its own nodes for some tags (for_statement, if_statement, tag_statement, …), so read the
  -- tag from the text: the first word after `{%`.
  return vim.treesitter.get_node_text(node, src):match('^%s*{%%%-?~?%s*([%w_]+)')
end

local function build(node, src)
  local t = node:type()
  if t == 'content' then return {} end -- a hole: the HTML tree fills it
  local s, e = B.byte_range(node)
  if t == 'ERROR' then
    local l = B.leaf('twig', 'ERROR', src, s, e, { readonly = true })
    return l and { l } or {}
  end
  if node:child_count() == 0 or ATOMIC[t] then
    local l = B.leaf('twig', t, src, s, e, t == 'comment' and { readonly = true } or nil)
    return l and { l } or {}
  end
  local children = {}
  for c in node:iter_children() do vim.list_extend(children, build(c, src)) end
  local b = B.composite('twig', t, children, { tag = t == 'statement_directive' and tag_name(node, src) or nil })
  return b and { b } or {}
end

local function pair(children)
  local root = { items = {} }
  local stack = { root }
  for _, c in ipairs(children) do
    local tag = c.tag
    local top = stack[#stack]
    if tag and OPENERS[tag] then
      c.pair_tag = true
      local p = { opener = tag, items = { c } }
      top.items[#top.items + 1] = p
      stack[#stack + 1] = p
    elseif tag and MIDDLES[tag] and top.opener then
      c.pair_tag = true
      top.items[#top.items + 1] = c
    elseif tag and top.opener and tag == 'end' .. top.opener then
      c.pair_tag = true
      top.items[#top.items + 1] = c
      table.remove(stack)
    else
      top.items[#top.items + 1] = c
    end
  end
  local function finish(p)
    local items = {}
    for _, it in ipairs(p.items) do
      items[#items + 1] = it.items and finish(it) or it
    end
    if not p.opener then return items end
    if p.opener == 'verbatim' and #items > 1 then
      -- Everything after `{% verbatim %}` keeps its text, the closing tag included.
      local open = items[1]
      local body = { lang = 'twig', type = 'verbatim_body', s = open.e, e = items[#items].e, readonly = true, synthetic = true, children = {} }
      return B.composite('twig', 'pair:verbatim', { open, body }, { synthetic = true })
    end
    return B.composite('twig', 'pair:' .. p.opener, items, { synthetic = true })
  end
  return finish(root)
end

function P.build(tree_root, src)
  local children = {}
  for c in tree_root:iter_children() do vim.list_extend(children, build(c, src)) end
  local s, e = B.trim_range(src, B.byte_range(tree_root))
  return B.composite('twig', 'template', pair(children), {}, { s, e })
end

--- Twig files use Twig's own indent Options; HTML's are ignored (Research Corpus: html.indent_size).
function P.indent_options() return 'twig' end

local BRACKETS = { ['['] = true, [']'] = true, ['{'] = true, ['}'] = true, ['('] = true, [')'] = true }

function P.child_indent(parent, child, style)
  local t = parent.type
  if t == 'template' then return 'none' end
  if t:match('^pair:') then
    if child.pair_tag then return 'none' end -- the pair's own tags
    return 'normal' -- the body, HTML or Twig
  end
  if t == 'array' or t == 'hash' or t == 'arguments' then
    return BRACKETS[child.type] and 'none' or 'normal' -- Twig uses only the normal indent
  end
  return 'none'
end

return P
