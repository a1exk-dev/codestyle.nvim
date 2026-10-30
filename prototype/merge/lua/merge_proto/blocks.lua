-- PROTOTYPE (throwaway): block constructors shared by the toy Language Plugins and the Core.
-- A block covers bytes [s, e) of the source. A leaf has no children. The formatter only changes gaps between leaves.
local M = {}

local function trim_range(src, s, e)
  while s < e and src:sub(s + 1, s + 1):match('%s') do s = s + 1 end
  while e > s and src:sub(e, e):match('%s') do e = e - 1 end
  return s, e
end
M.trim_range = trim_range

function M.byte_range(node)
  local _, _, s, _, _, e = node:range(true)
  return s, e
end

--- A leaf over [s, e), trimmed of whitespace. Returns nil for a whitespace-only range.
function M.leaf(lang, type, src, s, e, extra)
  s, e = trim_range(src, s, e)
  if s >= e then return nil end
  local b = { lang = lang, type = type, s = s, e = e }
  for k, v in pairs(extra or {}) do b[k] = v end
  return b
end

--- A composite block. Its range is the span of its children unless `range` is given.
function M.composite(lang, type, children, extra, range)
  if #children == 0 then return nil end
  local b = { lang = lang, type = type, children = children }
  if range then
    b.s, b.e = range[1], range[2]
  else
    b.s, b.e = children[1].s, children[#children].e
  end
  for k, v in pairs(extra or {}) do b[k] = v end
  return b
end

function M.is_leaf(b)
  return b.children == nil or b.readonly
end

function M.contains(a, b) return a.s <= b.s and b.e <= a.e end
function M.overlaps(a, b) return a.s < b.e and b.s < a.e end
function M.crosses(a, b) return M.overlaps(a, b) and not M.contains(a, b) and not M.contains(b, a) end

function M.leaves(root, out)
  out = out or {}
  if M.is_leaf(root) then
    out[#out + 1] = root
  else
    for _, c in ipairs(root.children) do M.leaves(c, out) end
  end
  return out
end

return M
