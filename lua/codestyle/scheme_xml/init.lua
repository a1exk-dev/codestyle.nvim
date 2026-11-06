-- The Scheme XML import (ADR-0010): it finds the source, reads it with the
-- strict reader, imports it and replaces the Draft with the result as one
-- undo step. One notice gives the totals; the report holds the details for
-- the Menu's report buffer. On any error the Draft is untouched.

local importer = require('codestyle.scheme_xml.importer')
local reader = require('codestyle.scheme_xml.reader')

--- The totals of an import, for its one notice.
---@class codestyle.ImportTotals
---@field imported integer
---@field left_out integer
---@field unknown integer
---@field invalid integer
---@field not_converted integer
---@field not_installed integer

--- What an import did, for the Menu's `R` report (ADR-0010).
---@class codestyle.ImportReport
---@field source string the file that was read
---@field languages codestyle.LanguageImport[] `general` first, then the installed languages by id
---@field not_installed string[] the `language=` names and custom elements that no installed plugin reads
---@field kept string[] the stored languages with no installed plugin: their values were not updated
---@field totals codestyle.ImportTotals

---@class codestyle.SchemeXml
--- The file to import: the repo's `.idea/codeStyles/Project.xml` when it exists, else `path`.
--- `codeStyleConfig.xml` and IDE scheme folders are never read.
---@field source fun(root?: string, path?: string): string?, string? nil and why when there is none
--- Imports into the Draft as one step. `root` is the repo root to look for `Project.xml` in, by default the
--- Draft's. Nil and the message (also given as an ERROR) when nothing was imported.
---@field import fun(draft: codestyle.Draft, opts?: { root?: string, path?: string }): codestyle.ImportReport?, string?

local M = {}

--- Where PhpStorm keeps a project's own Scheme XML, from the repo root.
M.project_xml = '.idea/codeStyles/Project.xml'

---@param deps { registry: codestyle.Registry, notices: codestyle.Notices }
---@return codestyle.SchemeXml
function M.new(deps)
  local scheme_importer = importer.new({ registry = deps.registry })

  ---@param root? string
  ---@param path? string
  ---@return string?
  ---@return string?
  local function source(root, path)
    local project = root and vim.fs.joinpath(root, M.project_xml)
    if project and vim.uv.fs_stat(project) then
      return project
    end
    if path then
      return vim.fs.normalize(vim.fn.fnamemodify(vim.fn.expand(path), ':p'))
    end
    return nil,
      ('no Scheme XML to import: %s does not exist and no path was given'):format(
        project or ('no repo root has ' .. M.project_xml)
      )
  end

  ---@param draft codestyle.Draft
  ---@param opts? { root?: string, path?: string }
  ---@return codestyle.ImportReport?
  ---@return string?
  local function run(draft, opts)
    opts = opts or {}
    local path, missing = source(opts.root or draft.root, opts.path)
    if not path then
      return nil, missing
    end
    local file, open_error = io.open(path, 'rb')
    if not file then
      return nil, ('cannot read %s: %s'):format(path, open_error)
    end
    local text = file:read('*a')
    file:close()
    local root, broken = reader.parse(text)
    local imported
    if root then
      local ok, result, problem = pcall(scheme_importer.import, root)
      if not ok then
        return nil, ('%s: %s; nothing was imported'):format(path, tostring(result))
      end
      imported, broken = result, problem
    end
    if not imported then
      ---@cast broken codestyle.XmlError
      return nil, ('%s:%d: %s; nothing was imported'):format(path, broken.line, broken.message)
    end
    draft.replace(imported.patch)

    ---@type codestyle.ImportTotals
    local totals = {
      imported = 0,
      left_out = 0,
      unknown = 0,
      invalid = 0,
      not_converted = 0,
      not_installed = #imported.not_installed,
    }
    for _, language in ipairs(imported.languages) do
      for kind in pairs(totals) do
        if kind ~= 'not_installed' then
          totals[kind] = totals[kind] + #language[kind]
        end
      end
    end
    ---@type codestyle.ImportReport
    local report = {
      source = path,
      languages = imported.languages,
      not_installed = imported.not_installed,
      kept = vim.tbl_map(function(kept)
        return kept.id
      end, draft.kept_languages()),
      totals = totals,
    }
    deps.notices.report(
      vim.log.levels.INFO,
      'always',
      'import',
      ('imported %s into the Draft: %d values, %d left out, %d unknown, %d invalid (defaults used), %d not converted, %d not installed'):format(
        path,
        totals.imported,
        totals.left_out,
        totals.unknown,
        totals.invalid,
        totals.not_converted,
        totals.not_installed
      )
    )
    return report
  end

  ---@type codestyle.SchemeXml
  return {
    source = source,
    import = function(draft, opts)
      local report, message = run(draft, opts)
      if not report then
        deps.notices.report(vim.log.levels.ERROR, 'always', 'import', message --[[@as string]])
      end
      return report, message
    end,
  }
end

return M
