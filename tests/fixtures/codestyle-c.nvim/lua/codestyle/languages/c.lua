-- The fake `c` Language Plugin (ADR-0017), on Neovim's bundled `c` parser.
-- Its `formatter.format` replaces the Core engine (ADR-0007).

---@type codestyle.Spec
return {
  api = 1,
  id = 'c',
  name = 'C',
  filetypes = { 'c' },
  parsers = { default = { 'c' } },
  options = {
    {
      key = 'spaces.around_assignment',
      type = 'boolean',
      default = false,
      label = 'Assignment operators (=)',
    },
  },
  formatter = 'codestyle.languages.c.formatter',
}
