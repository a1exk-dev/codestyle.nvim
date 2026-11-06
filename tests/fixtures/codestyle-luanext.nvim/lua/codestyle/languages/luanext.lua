-- A fake Language Plugin written for a newer `lua` grammar (ADR-0017): one of
-- its rules needs a node type that the bundled `lua` parser lacks (ADR-0002).

---@type codestyle.Spec
return {
  api = 1,
  id = 'luanext',
  name = 'Lua (newer grammar)',
  filetypes = { 'luanext' },
  parsers = { default = { 'lua' } },
  options = {
    {
      key = 'spaces.around_assignment',
      type = 'boolean',
      default = false,
      label = 'Assignment operators (=)',
    },
  },
  formatter = 'codestyle.languages.luanext.formatter',
}
