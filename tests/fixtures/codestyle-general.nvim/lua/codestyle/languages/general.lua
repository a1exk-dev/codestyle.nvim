-- A broken fake (ADR-0017): its id is the reserved `general` (ADR-0003).
-- It formats with the fake `lua` plugin's formatter, so that plugin must be
-- on the runtimepath too.

---@type codestyle.Spec
return {
  api = 1,
  id = 'general',
  name = 'general',
  filetypes = { 'general' },
  parsers = { default = { 'lua' } },
  options = {
    { key = 'spaces.around_assignment', type = 'boolean', default = false, label = 'Assignment operators (=)' },
  },
  formatter = 'codestyle.languages.lua.formatter',
}
