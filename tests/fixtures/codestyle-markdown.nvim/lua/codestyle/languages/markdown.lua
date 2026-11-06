-- The fake `markdown` Language Plugin (ADR-0017), on Neovim's bundled
-- `markdown` parser. It declares the on-marker quirk of ADR-0018: the line of
-- the on-marker belongs to the marker region, so it keeps its column.

---@type codestyle.Spec
return {
  api = 1,
  id = 'markdown',
  name = 'Markdown',
  filetypes = { 'markdown' },
  parsers = { default = { 'markdown' } },
  options = {},
  on_marker_in_region = true,
  formatter = 'codestyle.languages.markdown.formatter',
}
