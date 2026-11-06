-- A fake (ADR-0017) with the previous contract version, `api` 0, which still works (ADR-0007).
-- It formats with the fake `lua` plugin's formatter, so that plugin must be
-- on the runtimepath too.

---@type codestyle.Spec
return {
  api = 0,
  id = 'oldapi',
  name = 'oldapi',
  filetypes = { 'oldapi' },
  parsers = { default = { 'lua' } },
  options = {
    { key = 'spaces.around_assignment', type = 'boolean', default = false, label = 'Assignment operators (=)' },
  },
  formatter = 'codestyle.languages.lua.formatter',
}
