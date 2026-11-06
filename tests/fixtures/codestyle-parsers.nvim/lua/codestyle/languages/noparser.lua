-- A fake (ADR-0017) none of whose parsers is installed (ADR-0015, ADR-0014).
-- It formats with the fake `lua` plugin's formatter, so that plugin must be
-- on the runtimepath too.

---@type codestyle.Spec
return {
  api = 1,
  id = 'noparser',
  name = 'noparser',
  filetypes = { 'noparser' },
  parsers = { noparser = { 'no_such_parser_a', 'no_such_parser_b' }, default = { 'lua' } },
  options = {
    { key = 'spaces.around_assignment', type = 'boolean', default = false, label = 'Assignment operators (=)' },
  },
  formatter = 'codestyle.languages.lua.formatter',
}
