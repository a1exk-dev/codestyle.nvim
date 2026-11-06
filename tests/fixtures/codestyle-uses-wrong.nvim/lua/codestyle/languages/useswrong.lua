-- A broken fake (ADR-0017) that uses version 2 of the fake `lua`, which exports version 1.
-- It formats with the fake `lua` plugin's formatter, so that plugin must be
-- on the runtimepath too.

---@type codestyle.Spec
return {
  api = 1,
  id = 'useswrong',
  name = 'useswrong',
  filetypes = { 'useswrong' },
  parsers = { default = { 'lua' } },
  uses = { lua = 2 },
  options = {
    { key = 'spaces.around_assignment', type = 'boolean', default = false, label = 'Assignment operators (=)' },
  },
  formatter = 'codestyle.languages.lua.formatter',
}
