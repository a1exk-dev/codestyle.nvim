-- Block constructors for Language Plugins (ADR-0002, ADR-0007). A Block is a
-- part of the file that the engine places as one unit.

---@class codestyle.Block
---@field type string the type of the parser node it stands for, or a name the plugin gives a synthetic Block
---@field range integer[] `{ start_row, start_col, end_row, end_col }`, as `TSNode:range()`
---@field children codestyle.Block[] in text order
---@field indent? codestyle.Indent relative to the parent; nil is `none`
---@field wrap? codestyle.Wrap the wrap group whose line break may go before this Block
---@field alignment? codestyle.Alignment the alignment group of this Block
---@field embed? codestyle.EmbedPoint set on an Embed Point (`require('codestyle.embed')`)

---@class codestyle.BlockOpts
---@field node? TSNode the parser node the Block stands for
---@field type? string for a Block without a node: its type
---@field range? integer[] for a Block without a node, or to trim a node's range: `{ start_row, start_col, end_row, end_col }`
---@field children? codestyle.Block[]
---@field indent? codestyle.Indent
---@field wrap? codestyle.Wrap
---@field alignment? codestyle.Alignment

local M = {}

--- A Block over one parser node, or a synthetic Block over a range, such as
--- a word, a range trimmed of whitespace, or a pair of tags (ADR-0005).
---@param opts codestyle.BlockOpts
---@return codestyle.Block
function M.new(opts)
  local range = opts.range
  if not range then
    local start_row, start_col, end_row, end_col = assert(opts.node, 'a Block needs a node or a range'):range()
    range = { start_row, start_col, end_row, end_col }
  end
  return {
    type = opts.type or opts.node:type(),
    range = range,
    children = opts.children or {},
    indent = opts.indent,
    wrap = opts.wrap,
    alignment = opts.alignment,
  }
end

return M
