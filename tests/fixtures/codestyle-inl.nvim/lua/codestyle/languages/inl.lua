-- The fake template layer (ADR-0017, ADR-0005), on Neovim's bundled
-- `markdown_inline` parser. It claims no filetype: only the fake template
-- host embeds it. Its own indent size is never used in a template file,
-- because the host chooses the template layers' indent Options.

---@type codestyle.Spec
return {
  api = 1,
  id = 'inl',
  name = 'Inline',
  filetypes = {},
  parsers = { default = { 'markdown_inline' } },
  options = {
    { key = 'indent.size', type = 'integer', min = 0, max = 32, default = 4, label = 'Indent' },
  },
  formatter = 'codestyle.languages.inl.formatter',
}
