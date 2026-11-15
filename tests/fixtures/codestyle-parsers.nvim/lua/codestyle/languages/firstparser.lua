-- A fake (ADR-0017) whose first parser is not installed and whose second is (ADR-0015).
-- It formats with the fake `lua` plugin's formatter, so that plugin must be
-- on the runtimepath too.

---@type codestyle.Spec
return {
  api = 1,
  id = 'firstparser',
  name = 'firstparser',
  filetypes = { 'firstparser' },
  parsers = { default = { 'no_such_parser', 'lua' } },
  options = {
    { key = 'spaces.around_assignment', type = 'boolean', default = false, label = 'Assignment operators (=)' },
  },
  formatter = 'codestyle.languages.lua.formatter',
}
