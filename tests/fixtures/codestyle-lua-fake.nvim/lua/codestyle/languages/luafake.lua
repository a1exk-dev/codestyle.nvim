-- A fake (ADR-0017) that lists the dotted filetype `lua.fake` (ADR-0015).
-- It formats with the fake `lua` plugin's formatter, so that plugin must be
-- on the runtimepath too.

---@type codestyle.Spec
return {
  api = 1,
  id = 'luafake',
  name = 'luafake',
  filetypes = { 'lua.fake' },
  parsers = { default = { 'lua' } },
  options = {
    { key = 'spaces.around_assignment', type = 'boolean', default = false, label = 'Assignment operators (=)' },
  },
  formatter = 'codestyle.languages.lua.formatter',
}
