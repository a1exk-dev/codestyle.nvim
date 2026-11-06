-- Mixed line endings (ADR-0018): a run converts every line to the ending that
-- most lines use, with LF on a tie. A line ends with CRLF when it holds a
-- final `\r`, as in a buffer whose `fileformat` is `unix`.

local M = {}

--- The lines without their `\r`s when the endings are mixed, and `dos` when
--- CRLF wins. Lines with one ending come back as they are.
---@param lines string[]
---@return string[] lines
---@return 'dos'? fileformat `dos` when the lines now stand for CRLF lines
function M.convert(lines)
  local crlf = 0
  for _, line in ipairs(lines) do
    if line:sub(-1) == '\r' then
      crlf = crlf + 1
    end
  end
  if crlf == 0 or crlf == #lines then
    return lines, nil
  end
  local converted = {}
  for index, line in ipairs(lines) do
    converted[index] = line:sub(-1) == '\r' and line:sub(1, -2) or line
  end
  return converted, crlf > #lines - crlf and 'dos' or nil
end

return M
