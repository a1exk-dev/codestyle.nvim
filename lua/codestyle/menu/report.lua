-- The import report (ADR-0010): a pure function from what a Scheme XML import
-- did to the lines of the report buffer that `R` opens. For each language it
-- lists the imported values, the left-out fields, the unknown fields, the
-- invalid values with the default used, and what could not be converted.

local M = {}

---@param value any
---@return string
local function json(value)
  return vim.json.encode(value)
end

--- The report as lines.
---@param report codestyle.ImportReport
---@param name fun(id: string): string the name of an installed language
---@return string[]
function M.lines(report, name)
  local t = report.totals
  local lines = {
    'Imported ' .. report.source,
    ('%d values, %d left out, %d unknown, %d invalid (defaults used), %d not converted, %d not installed'):format(
      t.imported,
      t.left_out,
      t.unknown,
      t.invalid,
      t.not_converted,
      t.not_installed
    ),
  }

  ---@param title string
  ---@param items any[]
  ---@param text fun(item: any): string
  local function section(title, items, text)
    if #items > 0 then
      table.insert(lines, '  ' .. title)
      for _, item in ipairs(items) do
        table.insert(lines, '    ' .. text(item))
      end
    end
  end

  local function same(text)
    return text
  end

  for _, language in ipairs(report.languages) do
    table.insert(lines, '')
    table.insert(lines, name(language.id))
    if language.no_scheme then
      table.insert(lines, '  The Language Plugin reads no Scheme XML: its defaults are used')
    end
    section('Imported', language.imported, function(value)
      return ('%s = %s'):format(value.key, json(value.value))
    end)
    section('Left out (Options that v1 leaves out)', language.left_out, same)
    section('Unknown fields', language.unknown, same)
    section('Invalid (defaults used)', language.invalid, function(invalid)
      return ('%s: %s = %s: %s'):format(invalid.key, invalid.field, json(invalid.value), invalid.message)
    end)
    section('Not converted', language.not_converted, function(part)
      return ('%s: %s'):format(part.part, part.reason)
    end)
    if language.arrangement then
      table.insert(
        lines,
        language.arrangement == 'imported' and '  Arrangement imported'
          or '  Arrangement: no <arrangement>, default used'
      )
    end
    if #language.imported == 0 and not language.no_scheme then
      table.insert(lines, '  No values: every Option has its default')
    end
  end

  if #report.not_installed > 0 then
    table.insert(lines, '')
    table.insert(lines, 'Not installed (skipped; install the Language Plugin and import again)')
    for _, xml_name in ipairs(report.not_installed) do
      table.insert(lines, '    ' .. xml_name)
    end
  end
  if #report.kept > 0 then
    table.insert(lines, '')
    table.insert(lines, 'Not updated (no Language Plugin installed; the stored values stay)')
    for _, id in ipairs(report.kept) do
      table.insert(lines, '    ' .. id)
    end
  end
  return lines
end

return M
