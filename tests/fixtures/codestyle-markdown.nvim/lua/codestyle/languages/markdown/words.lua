-- Helpers of the fake markdown-like plugins: words as leaf Blocks, and the
-- range of a composite Block. Markdown grammars have no node for a word, and
-- their block nodes end after the line break.

local block = require('codestyle.block')

local M = {}

--- A leaf Block for each run of non-blank text in the range that lies
--- outside the `skip` ranges, in text order.
---@param source string
---@param range integer[]
---@param skip? integer[][]
---@return codestyle.Block[]
function M.in_range(source, range, skip)
  local lines = vim.split(source, '\n', { plain = true })
  ---@return boolean
  local function skipped(row, col)
    for _, part in ipairs(skip or {}) do
      local after_start = row > part[1] or (row == part[1] and col >= part[2])
      local before_end = row < part[3] or (row == part[3] and col < part[4])
      if after_start and before_end then
        return true
      end
    end
    return false
  end
  local words = {}
  for row = range[1], range[3] do
    local line = lines[row + 1] or ''
    local first = row == range[1] and range[2] or 0
    local last = row == range[3] and math.min(range[4], #line) or #line
    local word_start
    for col = first, last do
      local inside = col < last and not line:sub(col + 1, col + 1):match('%s') and not skipped(row, col)
      if inside and not word_start then
        word_start = col
      elseif not inside and word_start then
        table.insert(words, block.new({ type = 'word', range = { row, word_start, row, col } }))
        word_start = nil
      end
    end
  end
  return words
end

--- The range from the start of the first child to the end of the last one.
---@param children codestyle.Block[]
---@return integer[]
function M.span(children)
  local first, last = children[1].range, children[#children].range
  return { first[1], first[2], last[3], last[4] }
end

return M
