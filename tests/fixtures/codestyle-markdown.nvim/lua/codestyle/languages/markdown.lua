-- The fake `markdown` Language Plugin (ADR-0017), on Neovim's bundled
-- `markdown` parser. It is a host with Embed Points (ADR-0008): the body of a
-- fenced code block is a graft of the language that the info string names.
-- It declares the on-marker quirk of ADR-0018: the line of the on-marker
-- belongs to the marker region, so it keeps its column.

---@type codestyle.Spec
return {
  api = 1,
  id = 'markdown',
  name = 'Markdown',
  filetypes = { 'markdown' },
  parsers = { default = { 'markdown' } },
  options = {
    { key = 'indent.size', type = 'integer', min = 0, max = 32, default = 4, label = 'Indent' },
    { key = 'indent.use_tab', type = 'boolean', default = false, label = 'Use tab character' },
    {
      key = 'indent.same_in_whole_file',
      type = 'boolean',
      default = false,
      label = 'Use the same indent in fenced code',
    },
  },
  on_marker_in_region = true,
  formatter = 'codestyle.languages.markdown.formatter',
}
