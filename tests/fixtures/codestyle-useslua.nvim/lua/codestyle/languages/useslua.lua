-- A fake that uses the fake `lua` (ADR-0007), on the `lua` parser: it builds
-- with `lua`'s exported `build` and spaces `=` by `lua`'s Option.

---@type codestyle.Spec
return {
  api = 1,
  id = 'useslua',
  name = 'Uses Lua',
  filetypes = { 'useslua' },
  parsers = { default = { 'lua' } },
  uses = { lua = 1 },
  options = {},
  formatter = 'codestyle.languages.useslua.formatter',
}
