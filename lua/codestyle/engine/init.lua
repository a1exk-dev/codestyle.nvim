-- The Engine (ADR-0002): the IntelliJ Block model. It changes only the Gaps
-- between Blocks. Its interface to the rest of the Core is `layout`.

local read_only = require('codestyle.read_only')
local spacing = require('codestyle.engine.spacing')

local M = {}

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
---@param ctx codestyle.FormatContext
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

--- The Gap edits for the whole text, limited to `ctx.range`. Broken code and
--- the lines outside the range are read-only parts.
---@param ctx codestyle.FormatContext
---@param formatter codestyle.Formatter
---@return codestyle.Edit[] edits
---@return codestyle.Notice[] notices
function M.layout(ctx, formatter)
  local notices = {}
  local rules = usable_rules(ctx, formatter.rules or {}, notices)
  local parts = {}
  broken_parts(ctx.root, parts)
  if ctx.range then
    vim.list_extend(parts, read_only.outside(ctx.range))
  end
  local root = formatter.build(ctx)
  local lines = vim.split(ctx.source, '\n', { plain = true })
  return spacing.edits(root, lines, rules, ctx.values, read_only.new(parts)), notices
end

return M
