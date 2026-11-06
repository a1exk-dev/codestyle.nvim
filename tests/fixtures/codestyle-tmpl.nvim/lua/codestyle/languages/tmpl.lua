-- The fake template host (ADR-0017, ADR-0005), on Neovim's bundled
-- `markdown` parser. Its template layer is the fake `inl` language on
-- `markdown_inline`: every inline and every fenced body is a hole, and the
-- Core parses all of them as one combined text, so the two Block trees
-- interleave as PHP's and HTML's do. It needs the fake `markdown` plugin on
-- the runtimepath for the shared word helper.

---@type codestyle.Spec
return {
  api = 1,
  id = 'tmpl',
  name = 'Template',
  filetypes = { 'tmpl' },
  parsers = { default = { 'markdown' } },
  options = {
    { key = 'indent.size', type = 'integer', min = 0, max = 32, default = 4, label = 'Indent' },
  },
  formatter = 'codestyle.languages.tmpl.formatter',
}
