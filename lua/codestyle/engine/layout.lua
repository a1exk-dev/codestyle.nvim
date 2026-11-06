-- The whitespace pass of the Engine: a port of IntelliJ's block model
-- (`FormatProcessor`, `WrapProcessor`, `AlignmentHelper`). It changes only the
-- Gaps between leaf Blocks. The Gap before a leaf is owned by the lowest Block
-- that holds both sides, and that Block's rules give its Spacing.
--
-- One pass places the leaves in text order: the line feeds of each Gap, the
-- indent of each line from the parent chain, the spaces of each Gap on a line,
-- and Alignment. A line that passes the right margin records a wrap and starts
-- the pass again; a backward-shift Alignment that finds a column further right
-- does the same. Both only grow, so the passes end.

local M = {}

---@class codestyle.LayoutOptions
---@field spacing fun(parent: codestyle.Block, left: codestyle.Block, right: codestyle.Block): codestyle.Spacing?
---@field indent codestyle.IndentOptions
---@field right_margin integer the widest a line may be, in display columns

--- One leaf and the Gap before it.
---@class (private) codestyle.Leaf
---@field block codestyle.Block
---@field owner? codestyle.Block the Block that owns the Gap before the leaf, nil for the first leaf
---@field left? codestyle.Block the child of `owner` before the Gap
---@field chain codestyle.Block[] the Blocks that start at the leaf, outermost first, the leaf last
---@field spacing? codestyle.Spacing
---@field wraps codestyle.Wrap[] the wrap groups whose line break may go before the leaf
---@field alignment? codestyle.Alignment the outermost alignment group that starts at the leaf

--- Where one pass puts a leaf.
---@class (private) codestyle.Place
---@field line_feeds integer the line feeds of the Gap before the leaf
---@field col integer the display column of the leaf
---@field line integer the new line of the leaf's start
---@field keep boolean the Gap before the leaf keeps its text
---@field spaces integer the spaces of the Gap before the leaf, when it has no line feed

--- The leaves of the tree in text order, and the index of each Block's first leaf.
---@param root codestyle.Block
---@return codestyle.Leaf[], table<codestyle.Block, integer>
local function collect(root)
  local leaves, first_leaf = {}, {}

  ---@param block codestyle.Block
  ---@param owner? codestyle.Block
  ---@param left? codestyle.Block
  ---@param chain codestyle.Block[]
  local function walk(block, owner, left, chain)
    table.insert(chain, block)
    first_leaf[block] = #leaves + 1
    if #block.children == 0 then
      table.insert(leaves, { block = block, owner = owner, left = left, chain = chain })
      return
    end
    for index, child in ipairs(block.children) do
      if index == 1 then
        walk(child, owner, left, chain)
      else
        walk(child, block, block.children[index - 1], {})
      end
    end
  end

  walk(root, nil, nil, {})
  return leaves, first_leaf
end

---@param text string
---@return integer
local function width(text)
  return vim.api.nvim_strwidth(text)
end

---@param indent? codestyle.Indent
---@param options codestyle.IndentOptions
---@return integer
local function indent_columns(indent, options)
  local kind = indent and indent.kind
  if kind == 'normal' then
    return options.size
  elseif kind == 'continuation' then
    return options.continuation
  end
  return 0
end

--- The edits that give each Gap the layout that its Spacing, the Indents,
--- the Wraps and the Alignments ask for. A Gap that no rule covers keeps its
--- line breaks and its spaces; only the indent of a line it starts changes.
---@param root codestyle.Block
---@param lines string[]
---@param options codestyle.LayoutOptions
---@return codestyle.Edit[]
function M.edits(root, lines, options)
  local leaves, first_leaf = collect(root)

  -- What does not change between passes.
  local first_member = {} ---@type table<codestyle.Wrap, integer>
  for index, leaf in ipairs(leaves) do
    if leaf.owner then
      leaf.spacing = options.spacing(leaf.owner, leaf.left, leaf.chain[1])
    end
    leaf.wraps = {}
    for _, block in ipairs(leaf.chain) do
      if block.wrap then
        first_member[block.wrap] = first_member[block.wrap] or index
        if index ~= first_member[block.wrap] or block.wrap.wrap_first then
          table.insert(leaf.wraps, block.wrap)
        end
      end
      leaf.alignment = leaf.alignment or block.alignment
    end
  end

  ---@param leaf codestyle.Leaf
  ---@return integer start_row, integer start_col, integer end_row, integer end_col
  local function range(leaf)
    local range = leaf.block.range
    return range[1], range[2], range[3], range[4]
  end

  ---@param index integer
  ---@return integer
  local function leaf_end_row(index)
    return leaves[index].block.range[3]
  end

  local breaks = {} ---@type table<integer, true> leaves that a wrap if long puts on a new line
  local chopped = {} ---@type table<codestyle.Wrap, true> chop-down groups that do not fit
  local anchors = {} ---@type table<codestyle.Alignment, integer> columns of backward-shift groups

  --- One pass. Returns nil when a wrap was recorded, so the pass must run again.
  ---@return codestyle.Place[]?, table<codestyle.Alignment, integer>
  local function pass()
    local places = {} ---@type codestyle.Place[]
    local line_indent = {} ---@type table<integer, integer>
    local line, col, line_first = 0, 0, 1
    local aligned_line = {} ---@type table<codestyle.Alignment, integer>
    local first_col = {} ---@type table<codestyle.Alignment, integer>
    local widest = {} ---@type table<codestyle.Alignment, integer>

    for index, leaf in ipairs(leaves) do
      local start_row, start_col, end_row, end_col = range(leaf)
      local spacing = leaf.spacing
      local line_feeds, gap_width, keep = 0, 0, false
      if index == 1 then
        line_feeds = start_row
      else
        local _, _, prev_end_row, prev_end_col = range(leaves[index - 1])
        local old_line_feeds = start_row - prev_end_row
        if not spacing then
          line_feeds = old_line_feeds
        elseif old_line_feeds > 0 and spacing.keep_line_breaks then
          line_feeds = math.min(old_line_feeds, (spacing.keep_blank_lines or math.huge) + 1)
        end
        line_feeds = math.max(line_feeds, spacing and spacing.min_line_feeds or 0)
        if line_feeds == 0 then
          local wrapped = breaks[index]
          for _, wrap in ipairs(leaf.wraps) do
            wrapped = wrapped or chopped[wrap]
          end
          line_feeds = wrapped and 1 or 0
        end
        if line_feeds == 0 then
          if spacing and old_line_feeds > 0 then
            -- The Spacing joins the lines.
            gap_width = spacing.min_spaces
          else
            gap_width = width(lines[start_row + 1]:sub(prev_end_col + 1, start_col))
            keep = not spacing
            if spacing then
              gap_width = math.min(math.max(gap_width, spacing.min_spaces), spacing.max_spaces)
            end
          end
        end
      end

      local starts_line = index == 1 or line_feeds > 0
      local gap_start = col
      if starts_line then
        line = line + line_feeds
        line_first = index
        local base = leaf.owner and line_indent[places[first_leaf[leaf.owner]].line] or 0
        col = base
        for _, block in ipairs(leaf.chain) do
          col = col + indent_columns(block.indent, options.indent)
        end
      else
        col = col + gap_width
      end

      local alignment = leaf.alignment
      if alignment and aligned_line[alignment] ~= line then
        aligned_line[alignment] = line
        widest[alignment] = math.max(widest[alignment] or 0, col)
        local target = anchors[alignment] or first_col[alignment]
        if not target then
          first_col[alignment] = col
        elseif starts_line or col < target then
          keep = keep and col == target
          col = target
        end
      end

      if starts_line then
        line_indent[line] = col
      end
      places[index] = { line_feeds = line_feeds, col = col, line = line, keep = keep, spaces = col - gap_start }

      if start_row == end_row then
        col = col + width(lines[start_row + 1]:sub(start_col + 1, end_col))
      else
        line = line + end_row - start_row
        line_indent[line] = line_indent[places[index].line]
        line_first = index
        col = width(lines[end_row + 1]:sub(1, end_col))
      end

      if col > options.right_margin and start_row == end_row then
        for candidate = index, line_first + 1, -1 do
          local wrap = leaves[candidate].wraps[#leaves[candidate].wraps]
          if wrap and places[candidate].line_feeds == 0 then
            if wrap.type == 'chop_down' then
              chopped[wrap] = true
            else
              breaks[candidate] = true
            end
            return nil, widest
          end
        end
      end
    end
    return places, widest
  end

  local places ---@type codestyle.Place[]?
  repeat
    local widest
    places, widest = pass()
    if places then
      for alignment, column in pairs(widest) do
        if alignment.backward_shift and column > (anchors[alignment] or -1) then
          anchors[alignment] = column
          places = nil
        end
      end
    end
  until places
  ---@cast places codestyle.Place[]

  ---@param edit codestyle.Edit
  ---@return string
  local function old_text(edit)
    local rows = vim.list_slice(lines, edit.start_row + 1, edit.end_row + 1)
    rows[#rows] = rows[#rows]:sub(1, edit.end_col)
    rows[1] = rows[1]:sub(edit.start_col + 1)
    return table.concat(rows, '\n')
  end

  local edits = {}
  for index, leaf in ipairs(leaves) do
    local place = places[index]
    local start_row, start_col = range(leaf)
    local edit ---@type codestyle.Edit?
    if index == 1 or place.line_feeds > 0 and place.line_feeds == start_row - leaf_end_row(index - 1) then
      -- The line breaks stay; only the indent of the line changes.
      edit =
        { start_row = start_row, start_col = 0, end_row = start_row, end_col = start_col, text = (' '):rep(place.col) }
    elseif not place.keep then
      local _, _, prev_end_row, prev_end_col = range(leaves[index - 1])
      local text = place.line_feeds > 0 and ('\n'):rep(place.line_feeds) .. (' '):rep(place.col)
        or (' '):rep(place.spaces)
      edit =
        { start_row = prev_end_row, start_col = prev_end_col, end_row = start_row, end_col = start_col, text = text }
    end
    if edit and old_text(edit) ~= edit.text then
      table.insert(edits, edit)
    end
  end
  return edits
end

return M
