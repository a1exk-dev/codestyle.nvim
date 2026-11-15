-- The fake broken Language Plugin (#50, ADR-0016): its `build` raises an
-- error while the Option `build.raise` is on, as a Language Plugin with a bug
-- would on some values.

---@type codestyle.Spec
return {
  api = 1,
  id = 'broken',
  name = 'Broken',
  filetypes = { 'broken' },
  parsers = { default = { 'lua' } },
  options = {
    { key = 'build.raise', type = 'boolean', default = false, label = 'Raise an error in build' },
  },
  tabs = {
    { name = 'Errors', rows = { 'build.raise' }, sample = { 'x = 1' } },
  },
  formatter = 'codestyle.languages.broken.formatter',
}
