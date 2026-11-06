-- A broken fake (ADR-0017) that uses a language no installed plugin has.
-- It formats with the fake `lua` plugin's formatter, so that plugin must be
-- on the runtimepath too.

---@type codestyle.Spec
return {
  api = 1,
  id = 'usesmissing',
  name = 'usesmissing',
  filetypes = { 'usesmissing' },
  parsers = { default = { 'lua' } },
  uses = { absent = 1 },
  options = {
    { key = 'spaces.around_assignment', type = 'boolean', default = false, label = 'Assignment operators (=)' },
  },
  formatter = 'codestyle.languages.lua.formatter',
}
