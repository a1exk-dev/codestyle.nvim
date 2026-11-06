-- A broken fake (ADR-0017): a second Language Plugin with the id `lua`, which
-- the fake `lua` plugin already has (ADR-0003).

---@type codestyle.Spec
return {
  api = 1,
  id = 'lua',
  name = 'Lua clone',
  filetypes = { 'luaclone' },
  parsers = { default = { 'lua' } },
  options = {},
  formatter = 'codestyle.languages.lua.formatter',
}
