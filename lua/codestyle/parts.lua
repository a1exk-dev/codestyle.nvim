-- The parts of a file that an Embedded Language owns (ADR-0008): their
-- combined parse, and the text that the embedded plugin sees. The Engine and
-- Arrangement share them, so an embedded plugin gets the same `ctx` from both.

local text = require('codestyle.text')

local M = {}

--- The text of the lines with every byte outside the ranges turned into a
--- space, so an embedded plugin sees only its parts at their positions.
---@param lines string[]
---@param ranges integer[][] `{ start_row, start_col, end_row, end_col }`
---@return string
function M.mask(lines, ranges)
  local masked = {}
  for row, line in ipairs(lines) do
    masked[row] = (' '):rep(#line)
  end
  for _, range in ipairs(ranges) do
    for row = range[1], range[3] do
      local line = lines[row + 1]
      if line then
        local start_col = row == range[1] and range[2] or 0
        local end_col = row == range[3] and math.min(range[4], #line) or #line
        masked[row + 1] = masked[row + 1]:sub(1, start_col)
          .. line:sub(start_col + 1, end_col)
          .. masked[row + 1]:sub(end_col + 1)
      end
    end
  end
  return text.source(masked)
end

--- One parse of all the parts as one region: it sees only their text, with
--- the positions of the whole text, as an injection (ADR-0008).
---@param source string the whole text
---@param parser string
---@param ranges integer[][]
---@return TSNode root
function M.parse(source, parser, ranges)
  local tree = vim.treesitter.get_string_parser(source, parser)
  ---@diagnostic disable-next-line: invisible
  tree:set_included_regions({ vim.deepcopy(ranges) })
  return tree:parse(true)[1]:root()
end

return M
