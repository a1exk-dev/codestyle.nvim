-- The Arrangement Entry constructor for Language Plugins (ADR-0011). A
-- plugin's `entries(ctx)` returns a tree of them, and the Core's Arrangement
-- moves them.

--- One code element that Arrangement moves as a unit (ADR-0011).
---@class codestyle.ArrangementEntry
---@field range integer[] `{ start_row, start_col, end_row, end_col }`, with the comments and doc blocks that travel with the entry
---@field types string[] its entry types, from the spec's `arrangement.types`
---@field modifiers string[] its modifiers, from the spec's `arrangement.modifiers`
---@field name? string what a rule's `name` regex matches; an entry without one sorts after the named ones
---@field namespace? string what a rule's `namespace` regex matches
---@field children codestyle.ArrangementEntry[] in text order, arranged among themselves inside the entry
--- Keep-Together kind → the entries that follow this one, in order. With the
--- order `keep` or `by_name` they are the entries of its linked set (getters with
--- their setters, the methods of one parent); with `depth_first` or
--- `breadth_first` they are the entries it calls, which the Core walks.
---@field links table<string, codestyle.ArrangementEntry[]>

---@class codestyle.ArrangementEntryOpts
---@field node? TSNode the parser node of the entry
---@field range? integer[] the range when it is not exactly the node's, such as with a doc comment before it
---@field types string[]
---@field modifiers? string[]
---@field name? string
---@field namespace? string
---@field children? codestyle.ArrangementEntry[]
---@field links? table<string, codestyle.ArrangementEntry[]> set or fill them after the linked entries exist

local M = {}

--- An Arrangement Entry.
---@param opts codestyle.ArrangementEntryOpts
---@return codestyle.ArrangementEntry
function M.new(opts)
  local range = opts.range
  if not range then
    local start_row, start_col, end_row, end_col = assert(opts.node, 'an entry needs a node or a range'):range()
    range = { start_row, start_col, end_row, end_col }
  end
  return {
    range = range,
    types = opts.types,
    modifiers = opts.modifiers or {},
    name = opts.name,
    namespace = opts.namespace,
    children = opts.children or {},
    links = opts.links or {},
  }
end

return M
