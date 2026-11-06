-- Indent constructors for Blocks (ADR-0002, ADR-0007), a port of IntelliJ's
-- `Indent`. An Indent is relative to the parent Block, and the engine applies
-- it only when the Block starts a line: the line then starts at the indent of
-- the line where the parent starts, plus this Indent.

---@alias codestyle.IndentKind 'none'|'normal'|'continuation'

---@class codestyle.Indent
---@field kind codestyle.IndentKind

--- The sizes that the Indent kinds stand for, from a language's Options.
---@class codestyle.IndentOptions
---@field size integer the columns of a `normal` Indent
---@field continuation integer the columns of a `continuation` Indent
---@field use_tab? boolean write a line's indent with tabs, as far as whole tab stops go; default false
---@field tab_size? integer the columns of a tab; default 4

local M = {}

--- No indent: the Block starts at its parent's line indent.
---@return codestyle.Indent
function M.none()
  return { kind = 'none' }
end

--- One indent level, `IndentOptions.size` columns.
---@return codestyle.Indent
function M.normal()
  return { kind = 'normal' }
end

--- The indent of a line that continues a statement or expression,
--- `IndentOptions.continuation` columns.
---@return codestyle.Indent
function M.continuation()
  return { kind = 'continuation' }
end

return M
