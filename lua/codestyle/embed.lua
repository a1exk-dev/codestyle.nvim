-- The Embed Point constructor for host Language Plugins (ADR-0008, ADR-0005).
-- A host's `build` puts an Embed Point where code of another language is,
-- as a leaf of its Block tree. The Core parses the part with the Embedded
-- Language's own parser and plugin: a graft hangs the embedded Blocks under
-- one Block at this place; a template layer is a hole that the Core fills by
-- merging the Block tree of all the template parts of the file (ADR-0005).

---@class codestyle.EmbedPoint
---@field language string the Embedded Language id
---@field fragment? string the kind of code, such as `script`, given to the embedded `build` as `ctx.fragment`
---@field parser_key? string the key of the embedded spec's `parsers` table; nil is `default` (ADR-0015)
---@field template? boolean a template layer (merged, ADR-0005) instead of a graft

---@class codestyle.EmbedOpts: codestyle.EmbedPoint
---@field node? TSNode the host node that holds the part
---@field range? integer[] the part, `{ start_row, start_col, end_row, end_col }`, when there is no such node
---@field indent? codestyle.Indent the indent of the grafted Block relative to its host parent; nil is `none`

local block = require('codestyle.block')

local M = {}

--- An Embed Point: a leaf of the host's Block tree.
---@param opts codestyle.EmbedOpts
---@return codestyle.Block
function M.new(opts)
  local point = block.new({ node = opts.node, type = 'embed', range = opts.range, indent = opts.indent })
  point.type = 'embed'
  point.embed = {
    language = opts.language,
    fragment = opts.fragment,
    parser_key = opts.parser_key,
    template = opts.template == true,
  }
  return point
end

return M
