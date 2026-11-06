-- Spacing constructors for the `spacing` rule of Language Plugins (ADR-0007),
-- a port of IntelliJ's `Spacing.createSpacing`.

--- What the Gap between two adjacent Blocks may hold. When the Gap gets line
--- feeds, the spaces do not count: the line starts at the Block's indent.
---@class codestyle.Spacing
---@field min_spaces integer
---@field max_spaces integer
---@field min_line_feeds integer the line feeds the Gap gets at least
---@field keep_line_breaks boolean false joins the lines, down to `min_line_feeds`
---@field keep_blank_lines? integer the most blank lines that a kept line break keeps; nil keeps all

local M = {}

---@param min_spaces integer
---@param max_spaces integer the greater of the two counts is used
---@param min_line_feeds integer
---@param keep_line_breaks boolean
---@param keep_blank_lines? integer nil keeps all blank lines
---@return codestyle.Spacing
function M.create(min_spaces, max_spaces, min_line_feeds, keep_line_breaks, keep_blank_lines)
  return {
    min_spaces = min_spaces,
    max_spaces = math.max(min_spaces, max_spaces),
    min_line_feeds = min_line_feeds,
    keep_line_breaks = keep_line_breaks,
    keep_blank_lines = keep_blank_lines,
  }
end

--- Exactly `count` spaces on one line; line breaks and blank lines are kept.
---@param count integer
---@return codestyle.Spacing
function M.spaces(count)
  return M.create(count, count, 0, true)
end

return M
