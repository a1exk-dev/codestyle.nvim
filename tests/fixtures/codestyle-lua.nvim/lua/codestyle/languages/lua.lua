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
    { key = 'indent.keep_on_empty_lines', type = 'boolean', default = false, label = 'Keep indents on empty lines' },
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
  keep_indents_on_empty_lines = 'indent.keep_on_empty_lines',
  presets = {
    -- Sets its own language, `general` and the fake `alt` language (ADR-0006).
    {
      name = 'Roomy',
      values = {
        lua = { spaces = { around_assignment = true }, indent = { size = 2 } },
        general = { hard_wrap_at = 100 },
        alt = { spaces = { around_assignment = true } },
      },
    },
    -- One value that applies, and one of each kind that is skipped.
    {
      name = 'Mixed',
      values = {
        lua = { comments = { todo = 'XXX' }, ['spaces.before_paren'] = true, arrangement = { enabled = false } },
        alt = { spaces = { around_assignment = 'yes' } },
        c = { indent = { size = 2 } },
      },
    },
  },
  formatter = 'codestyle.languages.lua.formatter',
}
