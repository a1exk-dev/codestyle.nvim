-- Formatter markers (ADR-0018): the regions between an off-marker and the next
-- on-marker, which a format run keeps as read-only parts. The rules are
-- PhpStorm's: a tag is found anywhere, even in a string; in plain mode its
-- first character matches exactly and the rest ignores case; in regex mode it
-- is a case-sensitive Vim regex; there is no nesting, so the first on-marker
-- closes the region; an off-marker without an on-marker keeps the rest of the
-- file; the off-marker line is formatted.

local read_only = require('codestyle.read_only')

--- Finds a tag in a line from byte `init` (1-based). Returns the 1-based start
--- and inclusive end of the match, or nil.
---@alias codestyle.TagFinder fun(line: string, init: integer): integer?, integer?

---@class codestyle.Markers
--- The marker regions of the lines. With `on_line_in_region`, the line of the
--- on-marker belongs to the region (a spec flag for HTML, XML and JSON).
---@field regions fun(lines: string[], on_line_in_region?: boolean): codestyle.Part[]

local M = {}

---@param tag string
---@return codestyle.TagFinder?
local function plain(tag)
  if tag == '' then
    return nil
  end
  local first = tag:match('^[%z\1-\127\194-\244][\128-\191]*')
  local rest = tag:sub(#first + 1):lower()
  return function(line, init)
    local from = init
    while true do
      local start = line:find(first, from, true)
      if not start then
        return nil
      end
      local finish = start + #tag - 1
      if line:sub(start + #first, finish):lower() == rest then
        return start, finish
      end
      from = start + 1
    end
  end
end

---@param tag string
---@return codestyle.TagFinder?
---@return string? problem when the tag is not a valid Vim regex
local function regex(tag)
  if tag == '' then
    return nil
  end
  local ok, compiled = pcall(vim.regex, tag)
  if not ok then
    return nil, ('%q is not a valid Vim regex'):format(tag)
  end
  ---@cast compiled vim.regex
  return function(line, init)
    local start, finish = compiled:match_str(line:sub(init))
    if not start then
      return nil
    end
    return init + start, init + finish - 1
  end
end

--- The markers of the `general` values, or nil when markers are off.
---@param general codestyle.Values the resolved `general` values
---@return codestyle.Markers? markers nil when markers are off or a tag is broken
---@return string? problem why the markers are off, when a tag is broken
function M.new(general)
  local markers = general.markers
  if not markers.enabled then
    return nil
  end
  local finder = markers.regex and regex or plain
  local off, off_problem = finder(markers.off)
  local on, on_problem = finder(markers.on)
  if off_problem or on_problem then
    return nil, ('formatter marker %s; markers are off'):format(off_problem or on_problem)
  end
  if not off or not on then
    return nil
  end

  ---@type codestyle.Markers
  return {
    regions = function(lines, on_line_in_region)
      local parts = {} ---@type codestyle.Part[]
      local off_row ---@type integer?
      for row = 0, #lines - 1 do
        local line, init = lines[row + 1], 1
        -- `init` past the end stops a regex that matches empty text.
        while init <= #line + 1 do
          local start, finish = (off_row and on or off)(line, init)
          if not start then
            break
          end
          ---@cast finish integer
          if off_row then
            local last = on_line_in_region and row or row - 1
            if last > off_row then
              table.insert(parts, read_only.lines(off_row + 1, last))
            end
            off_row = nil
          else
            off_row = row
          end
          init = math.max(start, finish) + 1
        end
      end
      if off_row and off_row < #lines - 1 then
        table.insert(parts, read_only.lines(off_row + 1, #lines - 1))
      end
      return parts
    end,
  }
end

return M
