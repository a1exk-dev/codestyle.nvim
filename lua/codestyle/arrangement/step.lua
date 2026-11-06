-- The Arrangement step of the Format Run (ADR-0011, ADR-0002): it comes after
-- the marker regions are found and before the plugin's steps, and it ignores
-- markers (ADR-0018). The host's entries are arranged first. Then each graft
-- Embed Point of the host's Block tree is arranged with its own language's
-- Arrangement and `enabled`, as one part, so entries never cross it.

local arrangement = require('codestyle.arrangement')
local arrangement_lsp = require('codestyle.arrangement.lsp')
local parts = require('codestyle.parts')
local text = require('codestyle.text')

---@alias codestyle.ArrangementMode
---| 'auto' rearrange the languages whose Arrangement is enabled
---| 'force' rearrange every language, as `:Codestyle arrange`
---| 'off' never rearrange, as for the formatter's Behaviour Records
---| 'only' rearrange every language and format nothing, as PhpStorm's Rearrange Code; for the Arrangement cases

---@class codestyle.ArrangementStepRequest
---@field registry codestyle.Registry
---@field languages codestyle.Languages
---@field code_style codestyle.CodeStyle
---@field lines string[]
---@field language string
---@field parser string
---@field range? codestyle.Range
---@field mode codestyle.ArrangementMode
---@field buf? integer the buffer whose LSP clients serve `ctx.lsp`
---@field notices codestyle.Notice[] gets the step's notices
---@field parse fun(source: string, parser: string): TSNode parses the whole text, through the Preview's cache when it has one

---@class codestyle.ArrangementStepResult
---@field lines string[]
---@field range? codestyle.Range the request's range, grown to the lines of the entries that moved in it
---@field matches codestyle.ArrangementMatch[] in text order

local M = {}

---@param range? codestyle.Range
---@param span? codestyle.Range
---@return codestyle.Range?
local function grow(range, span)
  if not range or not span then
    return range
  end
  return {
    start_row = math.min(range.start_row, span.start_row),
    end_row = math.max(range.end_row, span.end_row),
  }
end

---@param block codestyle.Block
---@param found codestyle.Block[]
local function graft_points(block, found)
  if block.embed and not block.embed.template then
    table.insert(found, block)
  end
  for _, child in ipairs(block.children) do
    graft_points(child, found)
  end
end

---@param request codestyle.ArrangementStepRequest
---@return codestyle.ArrangementStepResult
function M.run(request)
  local lines, range, matches = request.lines, request.range, {}
  if request.mode == 'off' then
    return { lines = lines, range = range, matches = matches }
  end
  local registry = request.registry
  local lsp = arrangement_lsp.new(request.buf, request.notices)

  --- The Arrangement and plugin of a language that this run rearranges.
  ---@param id string
  ---@return codestyle.Arrangement?
  ---@return codestyle.ArrangementPlugin?
  local function plan(id)
    local spec = registry.get(id)
    if not (spec and spec.arrangement) then
      return nil
    end
    local stored = request.code_style.arrangement(id) --[[@as codestyle.Arrangement]]
    if request.mode == 'auto' and not stored.enabled then
      return nil
    end
    return stored, { spec = spec.arrangement, module = registry.load(id, 'arrangement') }
  end

  --- Rearranges once and applies the edits; earlier matches move with them.
  ---@param ctx codestyle.ArrangementContext
  ---@param stored codestyle.Arrangement
  ---@param plugin codestyle.ArrangementPlugin
  local function arrange(ctx, stored, plugin)
    local edits, found, span = arrangement.arrange(ctx, stored, plugin, lines)
    for _, match in ipairs(matches) do
      match.row, match.col = text.shift(match.row, match.col, edits)
      match.end_row, match.end_col = text.shift(match.end_row, match.end_col, edits)
    end
    vim.list_extend(matches, found)
    lines = text.apply(lines, edits)
    range = grow(range, span)
  end

  ---@param language codestyle.Language
  ---@param stored codestyle.Arrangement
  ---@param fields table
  ---@return codestyle.ArrangementContext
  local function context(language, stored, fields)
    return vim.tbl_extend('force', {
      language = language.id,
      values = language.values,
      uses = language.uses,
      range = range,
      arrangement = stored,
      lsp = lsp(language.id),
    }, fields)
  end

  local host = request.languages.get(request.language)
  local stored, plugin = plan(request.language)
  if stored and plugin then
    local source = text.source(lines)
    arrange(
      context(host, stored, {
        parser = request.parser,
        source = source,
        root = request.parse(source, request.parser),
      }),
      stored,
      plugin
    )
  end

  -- Embedded parts: only when the host has Blocks and another language has
  -- Arrangement, so a plain run builds nothing more.
  local others = vim.iter(registry.languages()):any(function(id)
    local spec = registry.get(id)
    return id ~= request.language and spec ~= nil and spec.arrangement ~= nil
  end)
  if host.formatter.build and others then
    local source = text.source(lines)
    local ctx = {
      language = request.language,
      parser = request.parser,
      root = request.parse(source, request.parser),
      source = source,
      values = host.values,
      uses = host.uses,
      range = range,
    }
    local points = {}
    graft_points(host.formatter.build(ctx) --[[@as codestyle.Block]], points)
    table.sort(points, function(a, b)
      return a.range[1] > b.range[1] or (a.range[1] == b.range[1] and a.range[2] > b.range[2])
    end)
    -- Back to front, so each part is still where the host's tree saw it.
    for _, point in ipairs(points) do
      local embed = point.embed --[[@as codestyle.EmbedPoint]]
      local language = request.languages.embedded(embed.language, embed.parser_key)
      local part_stored, part_plugin = nil, nil
      if language then
        part_stored, part_plugin = plan(language.id)
      end
      if language and part_stored and part_plugin then
        local part_source = text.source(lines)
        arrange(
          context(language, part_stored, {
            parser = language.parser,
            root = parts.parse(part_source, language.parser --[[@as string]], { point.range }),
            source = parts.mask(lines, { point.range }),
            fragment = embed.fragment,
          }),
          part_stored,
          part_plugin
        )
      end
    end
  end

  table.sort(matches, function(a, b)
    return a.row < b.row or (a.row == b.row and a.col < b.col)
  end)
  return { lines = lines, range = range, matches = matches }
end

return M
