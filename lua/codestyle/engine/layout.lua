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
--
-- A Gap that touches a read-only part keeps its line feeds and spaces, and a
-- line whose leading indent touches one keeps its indent; the pass places the
-- leaves after them from where they are. A line's indent change is its own
-- edit from column 0, so a range can free the indent of its first line.
--
-- Each Block has its own indent Options (ADR-0008): an Indent counts with the
-- Options of its Block, and a line's indent is written with the tab Options
-- of the line's first leaf.

local M = {}

---@class codestyle.LayoutOptions
---@field spacing fun(parent: codestyle.Block, left: codestyle.Block, right: codestyle.Block): codestyle.Spacing?
---@field indent fun(block: codestyle.Block): codestyle.IndentOptions the indent Options of the Block (ADR-0008)
---@field right_margin fun(block: codestyle.Block): integer the widest a line of the Block may be, in display columns
---@field read_only codestyle.ReadOnly the text that must not change

--- One leaf and the Gap before it.
---@class (private) codestyle.Leaf
---@field block codestyle.Block
---@field owner? codestyle.Block the Block that owns the Gap before the leaf, nil for the first leaf
---@field left? codestyle.Block the child of `owner` before the Gap
---@field chain codestyle.Block[] the Blocks that start at the leaf, outermost first, the leaf last
---@field spacing? codestyle.Spacing
---@field wraps codestyle.Wrap[] the wrap groups whose line break may go before the leaf
---@field alignment? codestyle.Alignment the outermost alignment group that starts at the leaf
---@field old_line_feeds integer the line feeds of the Gap before the leaf in the text
---@field fixed_gap boolean the Gap before the leaf keeps its line feeds, and its spaces on one line
---@field fixed_indent boolean the leaf keeps its column when it starts a line

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

--- The display width of text that starts at column 0.
---@param text string
---@param tab_size? integer
---@return integer
local function width(text, tab_size)
  if not tab_size or not text:find('\t') then
    return vim.api.nvim_strwidth(text)
  end
  local col = 0
  for char in text:gmatch('[^\t]*\t?') do
    local tab = char:sub(-1) == '\t'
    col = col + vim.api.nvim_strwidth(tab and char:sub(1, -2) or char)
    if tab then
      col = col + tab_size - col % tab_size
    end
  end
  return col
end

--- The whitespace of a line's indent: tabs as far as whole tab stops go when
--- the Options use tabs, then spaces.
---@param col integer
---@param options codestyle.IndentOptions
---@return string
local function render(col, options)
  if not options.use_tab then
    return (' '):rep(col)
  end
  local tab_size = options.tab_size or 4
  local tabs = math.floor(col / tab_size)
  return ('\t'):rep(tabs) .. (' '):rep(col - tabs * tab_size)
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

  ---@param leaf codestyle.Leaf
  ---@return integer start_row, integer start_col, integer end_row, integer end_col
  local function range(leaf)
    local block_range = leaf.block.range
    return block_range[1], block_range[2], block_range[3], block_range[4]
  end

  ---@return boolean
  local function touches(start_row, start_col, end_row, end_col)
    return options.read_only.touches({
      start_row = start_row,
      start_col = start_col,
      end_row = end_row,
      end_col = end_col,
      text = '',
    })
  end

  -- What does not change between passes.
  local first_member = {} ---@type table<codestyle.Wrap, integer>
  for index, leaf in ipairs(leaves) do
    local start_row, start_col = range(leaf)
    leaf.fixed_indent = touches(start_row, 0, start_row, start_col)
    if index == 1 then
      leaf.old_line_feeds, leaf.fixed_gap = start_row, true
    else
      local _, _, prev_end_row, prev_end_col = range(leaves[index - 1])
      leaf.old_line_feeds = start_row - prev_end_row
      if leaf.old_line_feeds > 0 then
        leaf.fixed_gap = leaf.fixed_indent or touches(prev_end_row, prev_end_col, start_row, 0)
      else
        leaf.fixed_gap = touches(prev_end_row, prev_end_col, start_row, start_col)
      end
      if not leaf.fixed_gap then
        leaf.spacing = options.spacing(leaf.owner, leaf.left, leaf.chain[1])
      end
    end
    leaf.wraps = {}
    for _, block in ipairs(leaf.chain) do
      if block.wrap then
        first_member[block.wrap] = first_member[block.wrap] or index
        local may_wrap = index ~= first_member[block.wrap] or block.wrap.wrap_first
        if may_wrap and not leaf.fixed_gap then
          table.insert(leaf.wraps, block.wrap)
        end
      end
      leaf.alignment = leaf.alignment or block.alignment
    end
  end

  local breaks = {} ---@type table<integer, true> leaves that a wrap if long puts on a new line
  local chopped = {} ---@type table<codestyle.Wrap, true> chop-down groups that do not fit
  local anchors = {} ---@type table<codestyle.Alignment, integer> columns of backward-shift groups

  --- The line feeds of the Gap before a leaf.
  ---@param index integer
  ---@param leaf codestyle.Leaf
  ---@return integer
  local function line_feeds_of(index, leaf)
    local old, spacing = leaf.old_line_feeds, leaf.spacing
    if leaf.fixed_gap or not spacing then
      return old
    end
    local line_feeds = 0
    if old > 0 and spacing.keep_line_breaks then
      line_feeds = math.min(old, (spacing.keep_blank_lines or math.huge) + 1)
    end
    line_feeds = math.max(line_feeds, spacing.min_line_feeds)
    if line_feeds == 0 then
      local wrapped = breaks[index]
      for _, wrap in ipairs(leaf.wraps) do
        wrapped = wrapped or chopped[wrap]
      end
      line_feeds = wrapped and 1 or 0
    end
    return line_feeds
  end

  --- The spaces of a Gap that stays on one line, and whether it keeps its text.
  ---@param index integer
  ---@param leaf codestyle.Leaf
  ---@return integer, boolean
  local function spaces_of(index, leaf)
    local spacing = leaf.spacing
    if spacing and leaf.old_line_feeds > 0 then
      -- The Spacing joins the lines.
      return spacing.min_spaces, false
    end
    local start_row, start_col = range(leaf)
    local _, _, _, prev_end_col = range(leaves[index - 1])
    local spaces = width(lines[start_row + 1]:sub(prev_end_col + 1, start_col))
    if not spacing then
      return spaces, true
    end
    return math.min(math.max(spaces, spacing.min_spaces), spacing.max_spaces), false
  end

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
      local line_feeds = index == 1 and start_row or line_feeds_of(index, leaf)
      local starts_line = index == 1 or line_feeds > 0
      local gap_start, keep, fixed = col, false, false
      if starts_line then
        line = line + line_feeds
        line_first = index
        fixed = leaf.fixed_indent
        if fixed then
          col = width(lines[start_row + 1]:sub(1, start_col), options.indent(leaf.block).tab_size)
        else
          col = leaf.owner and line_indent[places[first_leaf[leaf.owner]].line] or 0
          for _, block in ipairs(leaf.chain) do
            col = col + indent_columns(block.indent, options.indent(block))
          end
        end
      else
        local spaces
        spaces, keep = spaces_of(index, leaf)
        fixed = leaf.fixed_gap
        col = col + spaces
      end

      local alignment = leaf.alignment
      if alignment and aligned_line[alignment] ~= line then
        aligned_line[alignment] = line
        widest[alignment] = math.max(widest[alignment] or 0, col)
        local target = anchors[alignment] or first_col[alignment]
        if not target then
          first_col[alignment] = col
        elseif not fixed and (starts_line or col < target) then
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
        col = width(lines[end_row + 1]:sub(1, end_col), options.indent(leaf.block).tab_size)
      end

      if col > options.right_margin(leaf.block) and start_row == end_row then
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

  local edits = {}

  --- Adds the edit unless the text is already there.
  local function edit(start_row, start_col, end_row, end_col, text)
    local rows = vim.list_slice(lines, start_row + 1, end_row + 1)
    rows[#rows] = rows[#rows]:sub(1, end_col)
    rows[1] = rows[1]:sub(start_col + 1)
    if table.concat(rows, '\n') ~= text then
      table.insert(
        edits,
        { start_row = start_row, start_col = start_col, end_row = end_row, end_col = end_col, text = text }
      )
    end
  end

  for index, leaf in ipairs(leaves) do
    local place = places[index]
    local start_row, start_col = range(leaf)
    local prev_end_row, prev_end_col = 0, 0
    if index > 1 then
      local _
      _, _, prev_end_row, prev_end_col = range(leaves[index - 1])
    end
    local old = leaf.old_line_feeds
    if place.line_feeds > 0 and old > 0 or index == 1 then
      if place.line_feeds ~= old then
        edit(prev_end_row, prev_end_col, start_row, 0, ('\n'):rep(place.line_feeds))
      end
      if not leaf.fixed_indent then
        edit(start_row, 0, start_row, start_col, render(place.col, options.indent(leaf.block)))
      end
    elseif place.line_feeds > 0 then
      -- A new line in a Gap that had none.
      edit(
        prev_end_row,
        prev_end_col,
        start_row,
        start_col,
        ('\n'):rep(place.line_feeds) .. render(place.col, options.indent(leaf.block))
      )
    elseif not place.keep then
      edit(prev_end_row, prev_end_col, start_row, start_col, (' '):rep(place.spaces))
    end
  end
  return edits
end

return M
