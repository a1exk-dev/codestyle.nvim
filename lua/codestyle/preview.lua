-- The Preview (ADR-0016): it formats the sample of the Menu's current Tab with
-- the Draft and `parsers.default`, through the same Format Run as real
-- buffers. Keys never wait for it: a change of the Draft queues at most one
-- run with `vim.schedule`, so a held key skips values and the Preview always
-- ends on the latest Draft. A run that fails (the Format Run catches the
-- plugin's error) keeps the last good output and sets the failure marker; the
-- next good run clears it.

---@class codestyle.PreviewView
---@field buf integer the scratch buffer that shows the sample; its filetype is never a real one
---@field status fun(marker?: string) shows the failure marker, or clears it with nil

--- What the Preview shows: a language and one of its Tabs.
---@class codestyle.PreviewTarget
---@field language string the language id, `general` included
---@field tab codestyle.Tab

---@class codestyle.PreviewHandle
---@field show fun(target: codestyle.PreviewTarget) switches to a Tab; the run is queued
---@field detach fun() stops following the Draft

---@class codestyle.Preview
---@field attach fun(draft: codestyle.Draft, view: codestyle.PreviewView): codestyle.PreviewHandle

local M = {}

local ns = vim.api.nvim_create_namespace('codestyle.preview')

--- The 0-based rows of `new` that differ from `old`.
---@param old string[]
---@param new string[]
---@return integer[]
local function changed_rows(old, new)
  local diff = vim.text and vim.text.diff or vim.diff ---@diagnostic disable-line: deprecated
  local hunks = diff(table.concat(old, '\n') .. '\n', table.concat(new, '\n') .. '\n', { result_type = 'indices' })
  local rows = {} ---@type integer[]
  ---@cast hunks integer[][]
  for _, hunk in ipairs(hunks) do
    for row = hunk[3], hunk[3] + hunk[4] - 1 do
      table.insert(rows, row - 1)
    end
  end
  return rows
end

--- The text of a Tab that has no sample.
local NO_SAMPLE = { '', '  No Preview for this Tab.' }

---@param deps { registry: codestyle.Registry, format_run: codestyle.FormatRun, notices: codestyle.Notices }
---@return codestyle.Preview
function M.new(deps)
  --- The first parser of `parsers.default` that is installed.
  ---@param spec codestyle.Spec
  ---@return string?
  local function default_parser(spec)
    for _, parser in ipairs(spec.parsers.default or {}) do
      if vim.treesitter.language.add(parser) then
        return parser
      end
    end
  end

  ---@type codestyle.Preview
  return {
    attach = function(draft, view)
      local target ---@type codestyle.PreviewTarget?
      local queued, detached = false, false
      ---@type table<codestyle.Tab, string[]> the last good output of each Tab
      local last_good = {}
      ---@type table<codestyle.Tab, integer[]> the marked rows of each Tab's output
      local marked = {}
      local highlighted ---@type string? the language whose highlighting is on

      ---@param lines string[]
      ---@param rows? integer[] the 0-based rows to mark as changed
      local function set_lines(lines, rows)
        vim.bo[view.buf].modifiable = true
        vim.api.nvim_buf_set_lines(view.buf, 0, -1, false, lines)
        vim.bo[view.buf].modifiable = false
        vim.api.nvim_buf_clear_namespace(view.buf, ns, 0, -1)
        for _, row in ipairs(rows or {}) do
          vim.api.nvim_buf_set_extmark(view.buf, ns, row, 0, { line_hl_group = 'CodestylePreviewChanged' })
        end
      end

      --- Highlights the sample with Tree-sitter, else with the spec's Vim
      --- syntax. It never sets the filetype, so no ftplugin or LSP attaches.
      ---@param language string
      ---@param spec codestyle.Spec?
      ---@param parser string?
      local function highlight(language, spec, parser)
        if highlighted == language then
          return
        end
        highlighted = language
        pcall(vim.treesitter.stop, view.buf)
        vim.bo[view.buf].syntax = ''
        if parser and pcall(vim.treesitter.start, view.buf, parser) then
          return
        end
        if spec and spec.syntax then
          vim.bo[view.buf].syntax = spec.syntax
        end
      end

      local function run()
        queued = false
        if detached or not target or not vim.api.nvim_buf_is_valid(view.buf) then
          return
        end
        local language, tab = target.language, target.tab
        local spec = deps.registry.get(language)
        if not tab.sample or not spec then
          highlight('', nil, nil)
          set_lines(NO_SAMPLE)
          view.status(nil)
          return
        end
        local parser = default_parser(spec)
        highlight(language, spec, parser)
        if not parser then
          set_lines(tab.sample)
          view.status(('⚠ %s: no parser %s'):format(language, table.concat(spec.parsers.default or {}, ', ')))
          return
        end
        local result, failure = deps.format_run.run({
          lines = tab.sample,
          language = language,
          parser = parser,
          code_style = draft.code_style(),
        })
        if result then
          local previous = last_good[tab]
          if previous and not vim.deep_equal(previous, result.lines) then
            marked[tab] = changed_rows(previous, result.lines)
          end
          last_good[tab] = result.lines
          set_lines(result.lines, marked[tab])
          view.status(nil)
        else
          set_lines(last_good[tab] or tab.sample, marked[tab])
          view.status(('⚠ %s: formatter error'):format(language))
          deps.notices.report(
            vim.log.levels.ERROR,
            'always',
            'preview',
            ('the Preview of "%s" failed: %s'):format(language, (assert(failure)).message)
          )
        end
      end

      local function queue()
        if not queued then
          queued = true
          vim.schedule(run)
        end
      end

      local unsubscribe = draft.subscribe(queue)
      ---@type codestyle.PreviewHandle
      return {
        show = function(new_target)
          target = new_target
          queue()
        end,
        detach = function()
          detached = true
          unsubscribe()
        end,
      }
    end,
  }
end

return M
