-- Block constructors for Language Plugins (ADR-0002, ADR-0007). A Block is a
-- part of the file that the engine places as one unit.

---@class codestyle.Block
---@field type string the type of the parser node it stands for
---@field range integer[] `{ start_row, start_col, end_row, end_col }`, as `TSNode:range()`
---@field children codestyle.Block[] in text order
---@field indent? codestyle.Indent relative to the parent; nil is `none`
---@field wrap? codestyle.Wrap the wrap group whose line break may go before this Block
---@field alignment? codestyle.Alignment the alignment group of this Block

local M = {}

--- A Block over one parser node.
---@param opts { node: TSNode, children?: codestyle.Block[], indent?: codestyle.Indent, wrap?: codestyle.Wrap, alignment?: codestyle.Alignment }
---@return codestyle.Block
function M.new(opts)
  local start_row, start_col, end_row, end_col = opts.node:range()
  return {
    type = opts.node:type(),
    range = { start_row, start_col, end_row, end_col },
    children = opts.children or {},
    indent = opts.indent,
    wrap = opts.wrap,
    alignment = opts.alignment,
  }
end

return M
