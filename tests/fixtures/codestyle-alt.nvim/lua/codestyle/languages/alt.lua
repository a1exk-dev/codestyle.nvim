-- A second fake language (ADR-0017) for the choice of the plugin (ADR-0015).
-- It formats with the fake `lua` plugin's formatter, so that plugin must be
-- on the runtimepath too.

---@type codestyle.Spec
return {
  api = 1,
  id = 'alt',
  name = 'alt',
  filetypes = { 'alt' },
  parsers = { default = { 'lua' } },
  options = {
    { key = 'spaces.around_assignment', type = 'boolean', default = false, label = 'Assignment operators (=)' },
  },
  formatter = 'codestyle.languages.lua.formatter',
}
