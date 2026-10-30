-- PROTOTYPE (throwaway): a toy PHP Language Plugin. Only the rules the test files need.
local B = require('merge_proto.blocks')

local P = { id = 'php', parser = 'php' }

-- Nodes that the builder splices into their parent: they only glue `?> … <?php` or `: …` around HTML,
-- so as blocks they would cross HTML elements.
local SPLICE = { text_interpolation = true, colon_block = true }
-- Nodes kept as one leaf: their inside is text.
local ATOMIC = { string = true, encapsed_string = true, heredoc = true, nowdoc = true, comment = true, integer = true, float = true, name = true, variable_name = true }

local function build(node, src)
  local t = node:type()
  if t == 'text' then return {} end -- a hole: the HTML tree fills it
  local s, e = B.byte_range(node)
  if t == 'ERROR' then return { B.leaf('php', 'ERROR', src, s, e, { readonly = true }) } end
  if node:child_count() == 0 or ATOMIC[t] then
    local l = B.leaf('php', t, src, s, e)
    return l and { l } or {}
  end
  local children = {}
  for c in node:iter_children() do vim.list_extend(children, build(c, src)) end
  if SPLICE[t] then return children end
  local b = B.composite('php', t, children)
  return b and { b } or {}
end

--- Groups the program's children into regions `<?php … ?>`, so "Indent code in PHP tags" has a block to indent in.
local function regions(children)
  local out, cur = {}, nil
  for _, c in ipairs(children) do
    if c.type == 'php_tag' then
      if cur then out[#out + 1] = B.composite('php', 'php_region', cur, { synthetic = true }) end
      cur = { c }
    elseif cur then
      cur[#cur + 1] = c
      if c.type == 'php_end_tag' then
        out[#out + 1] = B.composite('php', 'php_region', cur, { synthetic = true })
        cur = nil
      end
    else
      out[#out + 1] = c
    end
  end
  if cur then out[#out + 1] = B.composite('php', 'php_region', cur, { synthetic = true }) end
  return out
end

function P.build(tree_root, src)
  local children = {}
  for c in tree_root:iter_children() do vim.list_extend(children, build(c, src)) end
  -- The root keeps its node range (holes included), trimmed of whitespace: like IntelliJ's PHP file group,
  -- it only joins a markup level whose host leaves span the whole file.
  local s, e = B.trim_range(src, B.byte_range(tree_root))
  return B.composite('php', 'program', regions(children), {}, { s, e })
end

--- Which language's indent Options apply to the whole file (Research Corpus: PHP files with inline HTML
--- take indent, continuation indent and tabs from the HTML Code Style).
function P.indent_options(has_embedded)
  return has_embedded and 'html' or 'php'
end

local TOKENS = {
  ['if'] = true, ['endif'] = true, ['else'] = true, ['elseif'] = true, ['foreach'] = true, ['endforeach'] = true,
  ['for'] = true, ['endfor'] = true, ['while'] = true, ['endwhile'] = true, [';'] = true, [':'] = true,
  php_tag = true, php_end_tag = true, parenthesized_expression = true, else_clause = true, else_if_clause = true,
  compound_statement = true, ['('] = true, [')'] = true, ['as'] = true,
}
local BRACED = { compound_statement = true, declaration_list = true, switch_block = true, enum_declaration_list = true }

function P.child_indent(parent, child, style)
  local t = parent.type
  local foreign = child.lang ~= 'php'
  if t == 'program' then return foreign and 'normal' or 'none' end
  if t == 'php_region' then
    if child.type == 'php_tag' or child.type == 'php_end_tag' then return 'none' end
    return style.indent_code_in_php_tags and 'normal' or 'none'
  end
  if foreign then return 'normal' end
  if BRACED[t] then return (child.type == '{' or child.type == '}') and 'none' or 'normal' end
  if t == 'array_creation_expression' then
    return (child.type == '[' or child.type == ']' or child.type == 'array' or child.type == '(' or child.type == ')') and 'none' or 'continuation'
  end
  if t == 'arguments' or t == 'formal_parameters' then
    return (child.type == '(' or child.type == ')') and 'none' or 'continuation'
  end
  if t == 'if_statement' or t == 'foreach_statement' or t == 'for_statement' or t == 'while_statement' then
    return TOKENS[child.type] and 'none' or 'normal' -- the body of the alternative syntax (`if (…): … endif;`)
  end
  return 'none'
end

return P
