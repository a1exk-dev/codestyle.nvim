-- The fake `c` plugin's `scheme` module (ADR-0010). It reads the blocks of
-- another language, as PHP reads HTML's indent.

---@type codestyle.Scheme
return {
  language = 'C',
  element = 'CCodeStyleSettings',
  entries = {
    { key = 'spaces.around_assignment', field = 'common:SPACE_AROUND_ASSIGNMENT_OPERATORS' },
    { key = 'embedded.lua_indent', field = 'lang:Lua:indent:INDENT_SIZE' },
    { key = 'embedded.lua_margin', field = 'lang:Lua:common:RIGHT_MARGIN' },
  },
}
