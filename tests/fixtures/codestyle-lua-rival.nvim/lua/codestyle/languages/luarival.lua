-- A fake (ADR-0017) that also claims the filetype `lua`, so the claim is a conflict (ADR-0015).
-- It formats with the fake `lua` plugin's formatter, so that plugin must be
-- on the runtimepath too.

---@type codestyle.Spec
return {
  api = 1,
  id = 'luarival',
  name = 'luarival',
  filetypes = { 'lua' },
  parsers = { default = { 'lua' } },
  options = {
    { key = 'spaces.around_assignment', type = 'boolean', default = false, label = 'Assignment operators (=)' },
  },
  formatter = 'codestyle.languages.lua.formatter',
}
