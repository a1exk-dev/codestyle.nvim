-- A broken fake (ADR-0017) with a contract version that the Core does not know.
-- It formats with the fake `lua` plugin's formatter, so that plugin must be
-- on the runtimepath too.

---@type codestyle.Spec
return {
  api = 2,
  id = 'future',
  name = 'future',
  filetypes = { 'future' },
  parsers = { default = { 'lua' } },
  options = {
    { key = 'spaces.around_assignment', type = 'boolean', default = false, label = 'Assignment operators (=)' },
  },
  formatter = 'codestyle.languages.lua.formatter',
}
