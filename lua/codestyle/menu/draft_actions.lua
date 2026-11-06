-- The Menu's keys that act on the whole Draft (ADR-0004, ADR-0006, ADR-0010):
-- "Set from…" (`p`) applies a Preset, `s` switches the scope, `i` imports a
-- Scheme XML and `R` shows the report of the last import. The Menu lends
-- them a Host: the Draft it shows, and how to show another one.

local report_view = require('codestyle.menu.report')
local scheme_xml = require('codestyle.scheme_xml')

local M = {}

--- What the Menu lends the actions.
---@class codestyle.menu.Host
---@field draft fun(): codestyle.Draft? the Draft that the Menu shows; nil when it is closed
---@field language fun(): string, string the id and the name of the current language
---@field name fun(id: string): string the name of General or of an installed language
---@field root fun(): string? the repo root of the buffer that the Menu was opened from
---@field focus fun() focuses the Options pane
---@field swap fun(draft: codestyle.Draft) shows another Draft in the Menu, at the same place
---@field settle fun(after: fun()) asks Save / Discard / Cancel when the Draft has changes; runs `after` unless cancelled

---@class codestyle.menu.DraftActions
---@field switch_scope fun() Global ↔ Project; the first switch in a repo with no Project Code Style offers how to start it
---@field set_from fun() "Set from…": picks a Preset of the current language and applies it
---@field import fun(path?: string) imports `Project.xml` of the repo, else `path`, else asks for a path
---@field report fun() opens the report of the last import into the shown Draft
---@field project_xml_found fun(): boolean the repo has `Project.xml` but no Project Code Style

---@param deps { presets: codestyle.Presets, scheme_xml: codestyle.SchemeXml, store: codestyle.Store, draft: (fun(scope: codestyle.Scope, root?: string): codestyle.Draft?, codestyle.BrokenFile?), notices: codestyle.Notices, host: codestyle.menu.Host }
---@return codestyle.menu.DraftActions
function M.new(deps)
  local host = deps.host

  --- The last import, and the Draft it went into.
  ---@type { draft: codestyle.Draft, report: codestyle.ImportReport }?
  local last

  ---@param message string
  local function info(message)
    deps.notices.report(vim.log.levels.INFO, 'always', 'menu', message)
  end

  local function set_from()
    local id, name = host.language()
    local items = deps.presets.list(id)
    if #items == 0 then
      info(name .. ' has no Presets')
      return
    end
    local draft = assert(host.draft())
    vim.ui.select(items, {
      prompt = ('Set %s from: '):format(name),
      format_item = function(item)
        return item.label
      end,
    }, function(item)
      if item and host.draft() == draft then
        deps.presets.apply(draft, item)
      end
    end)
  end

  ---@param draft codestyle.Draft
  ---@param path? string
  local function run_import(draft, path)
    local report = deps.scheme_xml.import(draft, { root = host.root(), path = path })
    last = report and { draft = draft, report = report } or nil
  end

  ---@param path? string
  local function import(path)
    local draft = assert(host.draft())
    if deps.scheme_xml.source(host.root(), path) then
      run_import(draft, path)
      return
    end
    vim.ui.input({ prompt = 'Import Scheme XML: ', completion = 'file' }, function(answer)
      answer = answer and vim.trim(answer)
      if answer and answer ~= '' and host.draft() == draft then
        run_import(draft, answer)
      end
    end)
  end

  --- Shows the Draft of a scope in the Menu.
  ---@param scope codestyle.Scope
  ---@return codestyle.Draft? nil when its file is broken
  local function show(scope)
    local draft, broken = deps.draft(scope, scope == 'project' and host.root() or nil)
    if not draft then
      ---@cast broken codestyle.BrokenFile
      deps.notices.report(
        vim.log.levels.ERROR,
        'always',
        'menu',
        ('%s:%d: %s; the Menu cannot open this Code Style'):format(broken.path, broken.line, broken.message)
      )
      return nil
    end
    host.swap(draft)
    return draft
  end

  --- The ways to start a Project Code Style (ADR-0004): each opens its Draft
  --- and makes the start one undo step, so that the save writes the file.
  ---@return { label: string, start: fun() }[]
  local function starts()
    local choices = {
      {
        label = 'Copy the Global Code Style',
        start = function()
          local global, broken = deps.store.load('global')
          if not global then
            ---@cast broken codestyle.BrokenFile
            deps.notices.report(
              vim.log.levels.ERROR,
              'always',
              'menu',
              ('%s:%d: %s; nothing was copied'):format(broken.path, broken.line, broken.message)
            )
            return
          end
          local draft = show('project')
          if draft then
            local patch = {} ---@type codestyle.Patch
            for id, values in pairs(global.raw().languages or {}) do
              patch[id] = type(values) == 'table' and vim.deepcopy(values) or nil
            end
            draft.apply(patch)
          end
        end,
      },
      {
        label = 'Start from the defaults',
        start = function()
          show('project')
        end,
      },
    }
    if vim.uv.fs_stat(vim.fs.joinpath(assert(host.root()), scheme_xml.project_xml)) then
      table.insert(choices, {
        label = 'Import ' .. scheme_xml.project_xml,
        start = function()
          local draft = show('project')
          if draft then
            run_import(draft)
          end
        end,
      })
    end
    return choices
  end

  local function switch_scope()
    local draft = assert(host.draft())
    local root = host.root()
    if draft.scope == 'global' and not root then
      deps.notices.report(
        vim.log.levels.WARN,
        'always',
        'menu',
        'no Project Code Style: the buffer is in no folder with .codestyle.json or .git'
      )
      return
    end
    host.settle(function()
      if host.draft() ~= draft then
        return
      end
      if draft.scope == 'project' then
        show('global')
      elseif vim.uv.fs_stat(deps.store.path('project', root)) then
        show('project')
      else
        vim.ui.select(starts(), {
          prompt = 'Start the Project Code Style: ',
          format_item = function(choice)
            return choice.label
          end,
        }, function(choice)
          if choice and host.draft() == draft then
            choice.start()
          end
        end)
      end
    end)
  end

  local function report()
    if not last or last.draft ~= host.draft() then
      info('no import to report; i imports a Scheme XML')
      return
    end
    local lines = report_view.lines(last.report, host.name)
    local buf = vim.api.nvim_create_buf(false, true)
    vim.bo[buf].bufhidden = 'wipe'
    vim.api.nvim_buf_set_name(buf, 'codestyle://report')
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.bo[buf].modifiable = false
    require('snacks').win({
      buf = buf,
      title = 'Import report',
      border = 'rounded',
      width = 0.8,
      height = 0.8,
      zindex = 100,
      backdrop = false,
      enter = true,
      wo = { wrap = false, number = false, relativenumber = false, signcolumn = 'no' },
      keys = { q = 'close', ['<Esc>'] = 'close', R = 'close' },
      on_close = function()
        if host.draft() then
          host.focus()
        end
      end,
    })
  end

  ---@type codestyle.menu.DraftActions
  return {
    switch_scope = switch_scope,
    set_from = set_from,
    import = import,
    report = report,
    project_xml_found = function()
      local root = host.root()
      return root ~= nil
        and vim.uv.fs_stat(vim.fs.joinpath(root, scheme_xml.project_xml)) ~= nil
        and vim.uv.fs_stat(deps.store.path('project', root)) == nil
    end,
  }
end

return M
