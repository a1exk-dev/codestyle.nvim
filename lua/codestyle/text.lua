-- Text helpers of the Format Run: apply edits to lines, and find the minimal
-- edits between two versions of the lines.

local M = {}

local diff = vim.text and vim.text.diff or vim.diff ---@diagnostic disable-line: deprecated

--- The lines with the edits applied, back to front. The edits must not
--- overlap. Of two edits at one position, the later one in the list is the
--- later one in the text.
---@param lines string[]
---@param edits codestyle.Edit[] positions in `lines`
---@return string[]
function M.apply(lines, edits)
  local order = {}
  for index = 1, #edits do
    order[index] = index
  end
  table.sort(order, function(i, j)
    local a, b = edits[i], edits[j]
    if a.start_row ~= b.start_row then
      return a.start_row > b.start_row
    end
    if a.start_col ~= b.start_col then
      return a.start_col > b.start_col
    end
    return i > j
  end)
  local result = vim.list_extend({}, lines)
  for _, index in ipairs(order) do
    local edit = edits[index]
    local prefix = result[edit.start_row + 1]:sub(1, edit.start_col)
    local suffix = result[edit.end_row + 1]:sub(edit.end_col + 1)
    local new = vim.split(prefix .. edit.text .. suffix, '\n', { plain = true })
    for _ = edit.start_row, edit.end_row do
      table.remove(result, edit.start_row + 1)
    end
    for index, line in ipairs(new) do
      table.insert(result, edit.start_row + index, line)
    end
  end
  return result
end

--- The 0-based offset of the start of each line in the text of `lines`
--- joined by `\n` with a final `\n`, and the length of that text last.
---@param lines string[]
---@return integer[]
local function line_starts(lines)
  local starts, offset = {}, 0
  for _, line in ipairs(lines) do
    table.insert(starts, offset)
    offset = offset + #line + 1
  end
  table.insert(starts, offset)
  return starts
end

---@param starts integer[]
---@param offset integer
---@return integer row 0-based
---@return integer col
local function position(starts, offset)
  local row = 1
  while starts[row + 1] <= offset and row + 1 < #starts do
    row = row + 1
  end
  return row - 1, offset - starts[row]
end

--- The minimal edits that turn `old` into `new`: one per changed hunk of
--- lines, trimmed to the characters that differ, so marks on unchanged text
--- stay in place.
---@param old string[]
---@param new string[]
---@return codestyle.Edit[] in text order
function M.diff(old, new)
  -- Both texts get a final `\n`, so a change at the end shows as a hunk.
  local a, b = table.concat(old, '\n') .. '\n', table.concat(new, '\n') .. '\n'
  local a_starts, b_starts = line_starts(old), line_starts(new)
  local hunks = diff(a, b, { result_type = 'indices' }) --[[@as integer[][] ]]
  local edits = {}
  for _, hunk in ipairs(hunks) do
    local a_line, a_count, b_line, b_count = unpack(hunk)
    -- A count of 0 means the hunk goes after that line.
    a_line = a_count == 0 and a_line + 1 or a_line
    b_line = b_count == 0 and b_line + 1 or b_line
    local s, e = a_starts[a_line], a_starts[a_line + a_count]
    local bs, be = b_starts[b_line], b_starts[b_line + b_count]
    while s < e and bs < be and a:byte(s + 1) == b:byte(bs + 1) do
      s, bs = s + 1, bs + 1
    end
    while e > s and be > bs and a:byte(e) == b:byte(be) do
      e, be = e - 1, be - 1
    end
    local text = b:sub(bs + 1, be)
    if e == #a then
      -- The span reaches the added final `\n`, which the buffer lacks. Move
      -- it one character back, over the `\n` before it.
      text = text == '' and '' or '\n' .. text:sub(1, -2)
      s, e = s - 1, e - 1
    end
    local start_row, start_col = position(a_starts, s)
    local end_row, end_col = position(a_starts, e)
    table.insert(
      edits,
      { start_row = start_row, start_col = start_col, end_row = end_row, end_col = end_col, text = text }
    )
  end
  return edits
end

return M
