-- The fake `lua` Language Plugin (ADR-0017), on Neovim's bundled `lua` parser.
-- It is the main fake: later tickets add the Options and rules they need.

---@type codestyle.Spec
return {
  api = 1,
  id = 'lua',
  name = 'Lua',
  filetypes = { 'lua' },
  parsers = { default = { 'lua' } },
  -- For the `uses` checks of the broken fakes (ADR-0007).
  exports = { version = 1 },
  options = {
    {
      key = 'spaces.around_assignment',
      type = 'boolean',
      -- Off, unlike PhpStorm's own defaults, so that a test can tell the
      -- default from a stored `true`.
      default = false,
      label = 'Assignment operators (=)',
    },
    {
      key = 'conversion.semicolons',
      type = 'boolean',
      default = false,
      label = 'Remove semicolons',
    },
    {
      key = 'conversion.double_quotes',
      type = 'boolean',
      default = false,
      label = 'Use double quotes',
    },
    { key = 'indent.size', type = 'integer', min = 0, max = 32, default = 4, label = 'Indent' },
    {
      key = 'wrap.call_arguments',
      type = 'choice',
      choices = {
        { id = 'off', label = 'Do not wrap' },
        { id = 'if_long', label = 'Wrap if long' },
        { id = 'chop_down', label = 'Chop down if long' },
      },
      default = 'off',
      label = 'Function call arguments',
    },
    {
      key = 'wrap.hard_wrap_at',
      type = 'integer',
      min = 1,
      max = 1000,
      inherit = 'hard_wrap_at',
      label = 'Hard wrap at',
    },
    {
      key = 'wrap.visual_guides',
      type = 'list',
      item = 'integer',
      min = 1,
      max = 1000,
      default = {},
      label = 'Visual guides',
    },
    { key = 'comments.todo', type = 'string', default = 'TODO', label = 'TODO marker' },
    { key = 'names.globals', type = 'list', item = 'string', default = { 'vim' }, label = 'Known globals' },
    {
      key = 'members.order',
      type = 'order',
      default = { 'fields', 'methods', 'metamethods' },
      label = 'Order of module members',
    },
    { key = 'spaces.after_comma', type = 'boolean', default = true, label = 'After comma' },
    {
      key = 'blank_lines.keep_in_code',
      type = 'integer',
      min = 0,
      max = 100,
      default = 2,
      label = 'Keep maximum blank lines in code',
    },
    {
      key = 'indent.continuation',
      type = 'integer',
      min = 0,
      max = 32,
      default = 8,
      label = 'Continuation indent',
    },
    { key = 'align.call_arguments', type = 'boolean', default = false, label = 'Align call arguments when multiline' },
    { key = 'align.table_fields', type = 'boolean', default = false, label = 'Align table fields in columns' },
  },
  migrations = {
    { key = 'spaces.assign', to = 'spaces.around_assignment' },
    { key = 'wrap.call_arguments', choice = 'chop', to = 'chop_down' },
  },
  formatter = 'codestyle.languages.lua.formatter',
}
