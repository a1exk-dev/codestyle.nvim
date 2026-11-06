-- The Engine (ADR-0002): the IntelliJ Block model. It changes only the Gaps
-- between Blocks. Its interface to the rest of the Core is `layout`.
--
-- Before the layout it resolves the Embed Points of the host's Block tree
-- (ADR-0008): it merges the template layer into the host tree (ADR-0005) and
-- grafts each other part with its own language's parser and plugin. Every
-- Block keeps the language that built it: the rules of a Gap's owner give its
-- Spacing, and each Block's indent Options are resolved per Block.

local merge = require('codestyle.engine.merge')
local parts_of = require('codestyle.parts')
local read_only = require('codestyle.read_only')
local layout = require('codestyle.engine.layout')
local right_margin = require('codestyle.engine.right_margin')

local M = {}

--- The sizes of the Indent kinds when the formatter does not give them, as
--- IntelliJ's defaults.
---@type codestyle.IndentOptions
local default_indent = { size = 4, continuation = 8, use_tab = false, tab_size = 4 }

--- The Spacing of the first rule that gives one, or nil to keep the Gap.
---@param rules codestyle.Rule[]
---@param values codestyle.Values
---@return fun(parent: codestyle.Block, left: codestyle.Block, right: codestyle.Block): codestyle.Spacing?
local function first_spacing(rules, values)
  return function(parent, left, right)
    for _, rule in ipairs(rules) do
      local spacing = rule.spacing and rule.spacing(parent, left, right, values)
      if spacing then
        return spacing
      end
    end
  end
end

--- The indent of a child whose parent belongs to the merge (ADR-0005): the
--- first rule that gives one, or nil.
---@param rules codestyle.Rule[]
---@param values codestyle.Values
---@return fun(parent: codestyle.Block, child: codestyle.Block): codestyle.Indent?
local function first_child_indent(rules, values)
  return function(parent, child)
    for _, rule in ipairs(rules) do
      local indent = rule.child_indent and rule.child_indent(parent, child, values)
      if indent then
        return indent
      end
    end
  end
end

--- The read-only parts of broken code: the lines of each `ERROR` node, and the
--- lines of the node that a `MISSING` node leaves open (ADR-0002).
---@param node TSNode
---@param parts codestyle.Part[]
local function broken_parts(node, parts)
  if node:missing() then
    local start_row, _, end_row = (node:parent() or node):range()
    table.insert(parts, read_only.lines(start_row, end_row))
  elseif node:has_error() then
    if node:type() == 'ERROR' then
      local start_row, _, end_row = node:range()
      table.insert(parts, read_only.lines(start_row, end_row))
    else
      for child in node:iter_children() do
        broken_parts(child, parts)
      end
    end
  end
end

--- The rules whose parser nodes and fields the grammar has. Each skipped rule
--- gives one warning per session.
---@param ctx { language: string, parser: string }
---@param rules codestyle.Rule[]
---@param notices codestyle.Notice[]
---@return codestyle.Rule[]
local function usable_rules(ctx, rules, notices)
  local grammar = vim.treesitter.language.inspect(ctx.parser)
  local fields = {}
  for _, field in ipairs(grammar.fields) do
    fields[field] = true
  end
  local usable = {}
  for _, rule in ipairs(rules) do
    local lacks
    for _, node in ipairs(rule.nodes or {}) do
      if not lacks and grammar.symbols[node] == nil and grammar.symbols['"' .. node .. '"'] == nil then
        lacks = ('the node type "%s"'):format(node)
      end
    end
    for _, field in ipairs(rule.fields or {}) do
      if not lacks and not fields[field] then
        lacks = ('the field "%s"'):format(field)
      end
    end
    if lacks then
      table.insert(notices, {
        level = vim.log.levels.WARN,
        scope = 'session',
        key = ('%s:%s:%s'):format(ctx.language, ctx.parser, lacks),
        message = ('Language Plugin "%s" has a rule that needs %s, which the "%s" parser lacks; the rule is skipped'):format(
          ctx.language,
          lacks,
          ctx.parser
        ),
      })
    else
      table.insert(usable, rule)
    end
  end
  return usable
end

--- What the layout needs of one language: its rules and its own indent
--- Options and right margin.
---@class (private) codestyle.Dialect
---@field spacing fun(parent: codestyle.Block, left: codestyle.Block, right: codestyle.Block): codestyle.Spacing?
---@field child_indent fun(parent: codestyle.Block, child: codestyle.Block): codestyle.Indent?
---@field indent codestyle.IndentOptions
---@field margin integer

--- What each Block is laid out with.
---@class (private) codestyle.BlockInfo
---@field dialect codestyle.Dialect the language that built the Block
---@field indent codestyle.IndentOptions resolved for the Block (ADR-0008)
---@field margin integer

--- The range without the whitespace at its ends, or nil when it holds none.
---@param lines string[]
---@param range integer[]
---@return integer[]?
local function trim(lines, range)
  local start_row, start_col, end_row, end_col = range[1], range[2], range[3], range[4]
  while true do
    local line = lines[start_row + 1] or ''
    local found = line:find('%S', start_col + 1)
    if found and (start_row < end_row or found <= end_col) then
      start_col = found - 1
      break
    end
    if start_row >= end_row then
      return nil
    end
    start_row, start_col = start_row + 1, 0
  end
  while true do
    local line = (lines[end_row + 1] or ''):sub(1, end_col)
    local last = line:find('%S%s*$')
    if last and (end_row > start_row or last > start_col) then
      end_col = last
      break
    end
    end_row = end_row - 1
    end_col = #(lines[end_row + 1] or '')
  end
  return { start_row, start_col, end_row, end_col }
end

---@param block codestyle.Block
---@param visit fun(block: codestyle.Block, parent?: codestyle.Block)
---@param parent? codestyle.Block
local function walk(block, visit, parent)
  visit(block, parent)
  for _, child in ipairs(block.children) do
    walk(child, visit, block)
  end
end

--- The Gap edits for the whole text, limited to `ctx.range`. Broken code, the
--- lines outside the range and the embedded parts that cannot be formatted
--- are read-only.
---@param ctx codestyle.FormatContext the host's
---@param languages codestyle.Languages
---@return codestyle.Edit[] edits
---@return codestyle.Notice[] notices
function M.layout(ctx, languages)
  local notices = {} ---@type codestyle.Notice[]
  local parts = {}
  broken_parts(ctx.root, parts)
  if ctx.range then
    vim.list_extend(parts, read_only.outside(ctx.range))
  end
  -- The source ends with a newline (`text.source`): its empty last line
  -- keeps every node position valid.
  local lines = vim.split(ctx.source, '\n', { plain = true })

  local dialects = {} ---@type table<string, codestyle.Dialect>
  ---@param language codestyle.Language
  ---@param parser string
  ---@return codestyle.Dialect
  local function dialect(language, parser)
    local key = language.id .. ':' .. parser
    if not dialects[key] then
      local formatter, values = language.formatter, language.values
      local rules = usable_rules({ language = language.id, parser = parser }, formatter.rules or {}, notices)
      dialects[key] = {
        spacing = first_spacing(rules, values),
        child_indent = first_child_indent(rules, values),
        indent = vim.tbl_extend(
          'force',
          default_indent,
          formatter.indent_options and formatter.indent_options(values) or {}
        ),
        margin = formatter.right_margin and formatter.right_margin(values) or values.general.hard_wrap_at,
      }
    end
    return dialects[key]
  end

  local host = languages.get(ctx.language)
  local file = dialect(host, ctx.parser)
  local override = host.formatter.override_indent_options ~= nil
    and host.formatter.override_indent_options(host.values) == true
  local info_of = {} ---@type table<codestyle.Block, codestyle.BlockInfo>
  ---@type codestyle.BlockInfo
  local file_info = { dialect = file, indent = file.indent, margin = file.margin }

  ---@param root codestyle.Block
  ---@param info codestyle.BlockInfo
  local function stamp(root, info)
    walk(root, function(block)
      info_of[block] = info_of[block] or info
    end)
  end

  ---@param no codestyle.NoLanguage
  local function report(no)
    if no.message then
      table.insert(notices, { level = vim.log.levels.WARN, scope = no.scope, key = no.key, message = no.message })
    end
  end

  --- A parse of the parts with the Embedded Language's parser, and its context.
  ---@param language codestyle.Language
  ---@param ranges integer[][]
  ---@param fragment? string
  ---@return codestyle.FormatContext
  local function embedded_context(language, ranges, fragment)
    local parser = language.parser --[[@as string]]
    local root = parts_of.parse(ctx.source, parser, ranges)
    broken_parts(root, parts)
    return {
      language = language.id,
      parser = parser,
      root = root,
      -- The plugin sees only the text of the parts.
      source = parts_of.mask(lines, ranges),
      values = language.values,
      uses = language.uses,
      range = ctx.range,
      fragment = fragment,
    }
  end

  --- The read-only leaf that keeps a part as written, or nil for a blank part.
  ---@param point codestyle.Block
  ---@param info codestyle.BlockInfo
  ---@return codestyle.Block?
  local function kept(point, info)
    local range = trim(lines, point.range)
    if not range then
      return nil
    end
    local leaf = { type = 'embedded', range = range, children = {}, indent = point.indent }
    info_of[leaf] = info
    return leaf
  end

  local graft_all

  --- The Block that a graft Embed Point becomes, or nil for a blank part.
  ---@param point codestyle.Block
  ---@param parent_info codestyle.BlockInfo
  ---@return codestyle.Block?
  local function graft(point, parent_info)
    local embed = point.embed --[[@as codestyle.EmbedPoint]]
    local language, no = languages.embedded(embed.language, embed.parser_key)
    if not language then
      report(no --[[@as codestyle.NoLanguage]])
      return kept(point, parent_info)
    end
    local built = language.formatter.build(embedded_context(language, { point.range }, embed.fragment))
    if not built then
      report({
        scope = 'buffer',
        key = language.id,
        message = ('Language Plugin "%s" builds no Blocks for "%s" code; it is kept as written'):format(
          language.id,
          embed.fragment or 'embedded'
        ),
      })
      return kept(point, parent_info)
    end
    if #built.children == 0 then
      return kept(point, parent_info)
    end
    local own = dialect(language, language.parser --[[@as string]])
    local children = built.children
    local first, last = children[1].range, children[#children].range
    -- The wrapper (IntelliJ's `AnotherLanguageBlockWrapper`): the host's indent,
    -- the embedded root's children.
    local wrapper = {
      type = built.type,
      range = { first[1], first[2], last[3], last[4] },
      children = children,
      indent = point.indent,
    }
    stamp(wrapper, {
      dialect = own,
      indent = override and file.indent or own.indent,
      margin = right_margin.of_graft(parent_info.margin, own.margin),
    })
    graft_all(wrapper)
    return wrapper
  end

  --- Replaces each graft Embed Point under the Block.
  ---@param block codestyle.Block
  graft_all = function(block)
    local children = {}
    for _, child in ipairs(block.children) do
      if child.embed then
        local grafted = graft(child, info_of[block] or file_info)
        if grafted then
          table.insert(children, grafted)
        end
      else
        graft_all(child)
        table.insert(children, child)
      end
    end
    block.children = children
  end

  --- Merges the template layer of the host tree (ADR-0005), if it has one.
  ---@param root codestyle.Block
  ---@return codestyle.Block
  local function merge_template(root)
    local holes = {} ---@type codestyle.Block[]
    walk(root, function(block)
      if block.embed and block.embed.template then
        table.insert(holes, block)
      end
    end)
    if #holes == 0 then
      return root
    end
    local embed = holes[1].embed --[[@as codestyle.EmbedPoint]]
    ---@param message? codestyle.NoLanguage
    local function as_grafts(message)
      if message then
        report(message)
      end
      for _, hole in ipairs(holes) do
        hole.embed.template = false
      end
      return root
    end
    local language, no = languages.embedded(embed.language, embed.parser_key)
    if not language then
      return as_grafts(no)
    end
    local markup_root = language.formatter.build(embedded_context(
      language,
      vim.tbl_map(function(hole)
        return hole.range
      end, holes),
      embed.fragment
    ))
    if not markup_root then
      return as_grafts({
        scope = 'buffer',
        key = language.id,
        message = ('Language Plugin "%s" builds no Blocks for "%s" code; it is kept as written'):format(
          language.id,
          embed.fragment or 'embedded'
        ),
      })
    end
    -- The template layers use the file's indent Options, which the host chooses.
    stamp(markup_root, {
      dialect = dialect(language, language.parser --[[@as string]]),
      indent = file.indent,
      margin = file.margin,
    })

    -- Holes make no Block; a host Block left with no children goes too.
    local is_hole = {}
    for _, hole in ipairs(holes) do
      is_hole[hole] = true
    end
    ---@param block codestyle.Block
    ---@return boolean keep
    local function drop_holes(block)
      if #block.children == 0 then
        return not is_hole[block]
      end
      block.children = vim.tbl_filter(drop_holes, block.children)
      return #block.children > 0
    end
    drop_holes(root)

    local parent_before = {} ---@type table<codestyle.Block, codestyle.Block>
    for _, tree in ipairs({ root, markup_root }) do
      walk(tree, function(block, parent)
        parent_before[block] = parent
      end)
    end
    local last = #lines
    local merged = merge.merge(root, markup_root, { 0, 0, last - 1, #lines[last] })
    -- A Block under a new parent gets its indent from the parent's plugin.
    walk(merged, function(child, parent)
      if parent and parent_before[child] ~= parent then
        local indent = info_of[parent].dialect.child_indent(parent, child)
        if not indent and info_of[parent].dialect == info_of[child].dialect then
          indent = child.indent
        end
        child.indent = indent
      end
    end)
    return merged
  end

  -- Only an embedded part's `build` may give nil.
  local root = host.formatter.build(ctx) --[[@as codestyle.Block]]
  stamp(root, file_info)
  root = merge_template(root)
  graft_all(root)

  ---@param block codestyle.Block
  ---@return codestyle.BlockInfo
  local function info(block)
    return info_of[block] or file_info
  end

  return layout.edits(root, lines, {
    spacing = function(parent, left, right)
      return info(parent).dialect.spacing(parent, left, right)
    end,
    indent = function(block)
      return info(block).indent
    end,
    right_margin = function(block)
      return info(block).margin
    end,
    read_only = read_only.new(parts),
  }),
    notices
end

return M
