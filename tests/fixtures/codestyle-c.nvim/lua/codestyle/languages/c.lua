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
  -- The sort panel of the CSS family (ADR-0012) over the top-level
  -- declarations, which stand for CSS declarations. Off by default, as
  -- PhpStorm's "Sort CSS properties".
  arrangement = {
    module = 'codestyle.languages.c.arrangement',
    panel = 'sort',
    types = { 'declaration' },
    name = true,
    custom_order = { 'color', 'width', 'align' },
    default = { enabled = true, aliases = {}, keep_together = {}, slots = {} },
    sample = { 'int width = 1;', 'int top = 2;', 'int color = 3;', 'int align = 4;' },
  },
}
