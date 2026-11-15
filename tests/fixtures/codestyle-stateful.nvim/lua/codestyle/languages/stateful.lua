-- A fake Language Plugin that breaks the rule of ADR-0016: its formatter
-- keeps state between runs, which the run-twice check of
-- `codestyle.testing` catches.

---@type codestyle.Spec
return {
  api = 1,
  id = 'stateful',
  name = 'Stateful',
  filetypes = { 'stateful' },
  parsers = { default = { 'lua' } },
  options = {},
  formatter = 'codestyle.languages.stateful.formatter',
}
