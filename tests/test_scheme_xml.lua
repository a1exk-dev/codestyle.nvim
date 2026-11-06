-- Scheme XML import (ADR-0010, ADR-0011, ADR-0018): the strict reader, the
-- importer and the sources, tested through the Draft that the import replaces,
-- the report it returns and the notices it gives. Regex Conversion (#50
-- module 9) is a named seam with one pinning test.

local H = dofile('tests/helpers.lua')
local expect = MiniTest.expect

local child = H.new_child()

local T = MiniTest.new_set({
  hooks = {
    pre_case = function()
      child:setup({ plugins = { 'codestyle-lua.nvim', 'codestyle-c.nvim' } })
    end,
    post_case = function()
      child:teardown()
    end,
  },
})

--- Opens the Draft of the Global Code Style in the child as `_G.draft`.
local function open_draft()
  child:services()
  child.lua("_G.draft = _G.core.draft('global')")
end

--- Writes a Scheme XML file and returns its path.
---@param text string
---@param path? string default `<case>/scheme.xml`
---@return string
local function write_xml(text, path)
  path = path or child.paths.root .. '/scheme.xml'
  child:write_file(path, text)
  return path
end

--- Imports into `_G.draft` through the public interface; returns the report,
--- or nil and the message.
---@param opts table `{ path?, root? }`
---@return table?, string?
local function import(opts)
  local results = child.lua('return { _G.core.scheme_xml.import(_G.draft, ...) }', { opts })
  local report, message = results[1], results[2]
  return report ~= vim.NIL and report or nil, message ~= vim.NIL and message or nil
end

--- The stored languages of the Draft.
---@return table
local function stored()
  return child.lua_get('_G.draft.code_style().raw().languages or vim.empty_dict()')
end

--- The report of one language.
---@param report table
---@param id string
---@return table
local function language(report, id)
  return assert(vim.iter(report.languages):find(function(each)
    return each.id == id
  end))
end

--- A `<code_scheme>` around the given lines.
---@param lines string[]
---@return string
local function scheme(lines)
  return table.concat(vim.list_extend({ '<code_scheme name="Project" version="173">' }, lines), '\n')
    .. '\n</code_scheme>\n'
end

T['Regex Conversion'] = MiniTest.new_set()

-- The named seam (#50 module 9): its temporary default converts the basic
-- subset and reports the rest. The PHP map settles the edge cases, and this
-- test shows each change as a diff.
T['Regex Conversion']['converts the basic subset and reports the rest'] = function()
  local results = child.lua(
    [[
    local from_java = require('codestyle.regex_conversion').from_java
    local results = {}
    for _, pattern in ipairs(...) do
      local converted, reason = from_java(pattern)
      table.insert(results, converted or ('! ' .. reason))
    end
    return results
  ]],
    {
      {
        'get.*',
        'foo|bar',
        '^get',
        'get$',
        '(?i)get.*',
        '[a-zA-Z]*get[a-zA-Z]*',
        '[^a-c]+x?',
        '\\w*get\\w*',
        '[\\w-]+\\d{2,3}',
        '(?:ab)+(cd)',
        'a\\.b\\*c\\[d~e',
        '\\Qa.b\\E',
        '@formatter:off',
        '\\t\\x41\\u00e9',
        '\\p{Lu}+',
        'a(?=b)',
        'a*?',
        'a(?i)b',
        '\\bword\\b',
        '(a)\\1',
        '[a[b]]',
        'a{2',
        '(a',
      },
    }
  )
  expect.equality(results, {
    'get.*',
    'foo\\|bar',
    '^get',
    'get$',
    '\\cget.*',
    '[a-zA-Z]*get[a-zA-Z]*',
    '[^a-c]\\+x\\=',
    '\\w*get\\w*',
    '[0-9A-Za-z_-]\\+\\d\\{2,3}',
    '\\%(ab\\)\\+\\(cd\\)',
    'a\\.b\\*c\\[d\\~e',
    'a\\.b',
    '@formatter:off',
    '\\t\\%x41\\%u00e9',
    '! cannot convert \\p',
    '! cannot convert (?=',
    '! cannot convert a lazy or possessive quantifier',
    '! cannot convert (?i) after the start',
    '! cannot convert \\b',
    '! cannot convert \\1',
    '! cannot convert a nested character class',
    '! cannot convert an unclosed {',
    '! cannot convert an unclosed (',
  })
end

T['reader'] = MiniTest.new_set()

T['reader']['accepts comments, declarations, both quotes, entities, references and CDATA'] = function()
  open_draft()
  local path = write_xml(table.concat({
    '<?xml version="1.0" encoding="UTF-8"?>',
    '<!-- exported by hand -->',
    "<code_scheme name='Project' version='173'>",
    '  <LuaCodeStyleSettings>',
    '    <option name="TODO_MARKER" value="&lt;&amp;&gt;&quot;&apos;&#65;&#x42;" />',
    "    <option name='KNOWN_GLOBALS' value='vim,jit'/>",
    '  </LuaCodeStyleSettings>',
    '  <codeStyleSettings language="Lua">',
    '    <arrangement><rules><section><rule>',
    '      <match><NAME><![CDATA[a<b]]></NAME></match>',
    '    </rule></section></rules></arrangement>',
    '  </codeStyleSettings>',
    '</code_scheme>',
  }, '\n'))
  local report = assert(import({ path = path }))
  expect.no_equality(report, nil)
  local lua = stored().lua
  expect.equality(lua.comments.todo, '<&>"\'AB')
  expect.equality(lua.names.globals, { 'vim', 'jit' })
  expect.equality(lua.arrangement.slots, { { { name = 'a<b' } } })
end

T['reader']['malformed XML gives one error with the line, and the Draft is unchanged'] = function()
  child:write_global({ version = 1, languages = { lua = { indent = { size = 2 } } } })
  open_draft()
  for _, case in ipairs({
    { text = '<code_scheme>\n  <LuaCodeStyleSettings>\n  </CCodeStyleSettings>\n</code_scheme>', line = 3 },
    { text = '<?xml version="1.0"?>\n<!DOCTYPE x [ <!ENTITY a "b"> ]>\n<code_scheme/>', line = 2 },
    { text = '<code_scheme>\n<option name="A" value="&nbsp;"/>\n</code_scheme>', line = 2 },
    { text = '<code_scheme>\n<option name="A" value="1"', line = 2 },
  }) do
    child.lua('_G.test_notices = {}')
    local report, message = import({ path = write_xml(case.text) })
    expect.equality(report, nil)
    local notices = child:notices()
    expect.equality(#notices, 1)
    expect.equality(notices[1].level, H.levels.ERROR)
    expect.equality(notices[1].message, 'codestyle: ' .. message)
    expect.equality(
      assert(message):match('^' .. vim.pesc(child.paths.root .. '/scheme.xml:') .. '(%d+):'),
      tostring(case.line)
    )
    expect.equality(stored(), { lua = { indent = { size = 2 } } })
    expect.equality(child.lua_get('_G.draft.undo()'), false)
  end
end

T['importer'] = MiniTest.new_set()

T['importer']['every address form resolves'] = function()
  open_draft()
  local report = assert(import({
    path = write_xml(scheme({
      '  <option name="RIGHT_MARGIN" value="100" />',
      '  <option name="OTHER_INDENT_OPTIONS">',
      '    <value>',
      '      <option name="CONTINUATION_INDENT_SIZE" value="6" />',
      '    </value>',
      '  </option>',
      '  <CCodeStyleSettings>',
      '    <option name="USE_DOUBLE_QUOTES" value="true" />',
      '  </CCodeStyleSettings>',
      '  <LuaCodeStyleSettings>',
      '    <option name="TODO_MARKER" value="FIXME" />',
      '  </LuaCodeStyleSettings>',
      '  <codeStyleSettings language="Lua">',
      '    <option name="SPACE_AROUND_ASSIGNMENT_OPERATORS" value="true" />',
      '    <option name="RIGHT_MARGIN" value="80" />',
      '    <indentOptions>',
      '      <option name="INDENT_SIZE" value="2" />',
      '    </indentOptions>',
      '  </codeStyleSettings>',
      '  <codeStyleSettings language="C">',
      '    <option name="SPACE_AROUND_ASSIGNMENT_OPERATORS" value="true" />',
      '  </codeStyleSettings>',
    })),
  }))
  expect.equality(stored(), {
    general = { hard_wrap_at = 100 },
    lua = {
      spaces = { around_assignment = true },
      wrap = { hard_wrap_at = 80 },
      indent = { size = 2, continuation = 6 },
      comments = { todo = 'FIXME' },
      conversion = { double_quotes = true },
    },
    c = {
      spaces = { around_assignment = true },
      embedded = { lua_indent = 2, lua_margin = 80 },
    },
  })
  -- A field that another language reads is neither unknown nor left out.
  for _, each in ipairs(report.languages) do
    expect.equality({ each.id, each.unknown, each.left_out }, { each.id, {}, {} })
  end
end

T['importer']['converts values by type; an absent field or -1 leaves the default'] = function()
  open_draft()
  import({
    path = write_xml(scheme({
      '  <option name="FORMATTER_TAGS_ENABLED" value="false" />',
      '  <option name="DO_NOT_FORMAT">',
      '    <list>',
      '      <fileSet type="globPattern" pattern="*.min.lua" />',
      '      <fileSet type="globPattern" pattern="vendor/**" />',
      '    </list>',
      '  </option>',
      '  <LuaCodeStyleSettings>',
      '    <option name="KNOWN_GLOBALS" value="vim, jit ,love" />',
      '    <option name="METHODS_WEIGHT" value="0" />',
      '  </LuaCodeStyleSettings>',
      '  <codeStyleSettings language="Lua">',
      '    <option name="CALL_PARAMETERS_WRAP" value="2" />',
      '    <option name="RIGHT_MARGIN" value="-1" />',
      '    <option name="SOFT_MARGINS" value="80,100" />',
      '  </codeStyleSettings>',
    })),
  })
  expect.equality(stored(), {
    general = { markers = { enabled = false }, do_not_format = { '*.min.lua', 'vendor/**' } },
    lua = {
      names = { globals = { 'vim', 'jit', 'love' } },
      members = { order = { 'methods', 'fields', 'metamethods' } },
      wrap = { call_arguments = 'chop_down', visual_guides = { 80, 100 } },
    },
  })
end

T['importer']['replaces general and every installed language as one undo step'] = function()
  child:write_global({
    version = 1,
    languages = {
      general = { hard_wrap_at = 80 },
      lua = { indent = { size = 2 }, spaces = { around_assignment = true }, arrangement = { enabled = false } },
      c = { spaces = { around_assignment = true } },
      php = { indent = { size = 3 } },
    },
  })
  open_draft()
  local before = stored()
  local report = assert(import({
    path = write_xml(scheme({
      '  <codeStyleSettings language="Lua">',
      '    <indentOptions><option name="INDENT_SIZE" value="8" /></indentOptions>',
      '  </codeStyleSettings>',
      '  <PHPCodeStyleSettings><option name="ALIGN_ASSIGNMENTS" value="true" /></PHPCodeStyleSettings>',
      '  <codeStyleSettings language="PHP"><option name="RIGHT_MARGIN" value="100" /></codeStyleSettings>',
    })),
  }))
  expect.equality(stored(), {
    lua = { indent = { size = 8 } },
    c = { embedded = { lua_indent = 8 } },
    php = { indent = { size = 3 } },
  })
  expect.equality(report.kept, { 'php' })
  expect.equality(report.not_installed, { 'PHP', 'PHPCodeStyleSettings' })
  expect.equality(child.lua_get('_G.draft.undo()'), true)
  expect.equality(stored(), before)
  expect.equality(child.lua_get('_G.draft.undo()'), false)
end

T['importer']['converts <arrangement> through the phpstorm map'] = function()
  open_draft()
  local report = assert(import({
    path = write_xml(scheme({
      '  <codeStyleSettings language="Lua">',
      '    <arrangement>',
      '      <tokens>',
      '        <token id="visibility" name="visibility">',
      '          <rules>',
      '            <rule><match><PRIVATE>false</PRIVATE></match></rule>',
      '            <rule><match><PRIVATE>true</PRIVATE></match></rule>',
      '          </rules>',
      '        </token>',
      '      </tokens>',
      '      <groups>',
      '        <group><type>DEPENDENT_METHODS</type><order>BREADTH_FIRST</order></group>',
      '        <group><type>NO_SUCH</type><order>KEEP</order></group>',
      '      </groups>',
      '      <rules>',
      '        <section>',
      '          <start_comment>// fields</start_comment>',
      '          <rule><match><AND><FIELD>true</FIELD><visibility /></AND></match></rule>',
      '        </section>',
      '        <section>',
      '          <rule><match><AND><METHOD>true</METHOD><NAME>(?i)get.*</NAME></AND></match><order>BY_NAME</order></rule>',
      '          <rule><match><NAME>\\p{Lu}+</NAME></match></rule>',
      '          <rule><match><OR><FIELD>true</FIELD><METHOD>true</METHOD></OR></match></rule>',
      '          <rule><match><STATIC>true</STATIC></match></rule>',
      '        </section>',
      '        <section><rule><match><FUNCTION>true</FUNCTION></match></rule></section>',
      '      </rules>',
      '    </arrangement>',
      '  </codeStyleSettings>',
    })),
  }))
  expect.equality(stored().lua.arrangement, {
    aliases = { visibility = { { is_not = { 'private' } }, { is = { 'private' } } } },
    keep_together = { { kind = 'dependent_methods', order = 'breadth_first' } },
    slots = {
      { { is = { 'field' }, alias = 'visibility' } },
      { { is = { 'method' }, name = '\\cget.*', order = 'by_name' } },
      { { is = { 'function' } } },
    },
  })
  local lua = language(report, 'lua')
  expect.equality(lua.arrangement, 'imported')
  expect.equality(lua.not_converted, {
    { part = 'arrangement: Keep-Together NO_SUCH', reason = 'unknown Keep-Together kind' },
    { part = 'arrangement: Slot 1 comment', reason = 'Slot comments are not kept' },
    { part = 'arrangement: Slot 2 rule 2', reason = 'cannot convert the Java regex "\\p{Lu}+": cannot convert \\p' },
    { part = 'arrangement: Slot 2 rule 3', reason = 'cannot convert <OR>' },
    { part = 'arrangement: Slot 2 rule 4', reason = 'unknown token STATIC' },
  })
end

T['importer']['a language with no <arrangement> gets the default'] = function()
  child:write_global({ version = 1, languages = { lua = { arrangement = { enabled = false } } } })
  open_draft()
  local report = assert(import({ path = write_xml(scheme({ '  <codeStyleSettings language="Lua" />' })) }))
  expect.equality(stored(), {})
  expect.equality(language(report, 'lua').arrangement, 'default')
end

T['importer']['the report lists every outcome, and one notice gives the totals'] = function()
  open_draft()
  local path = write_xml(scheme({
    '  <option name="RIGHT_MARGIN" value="100" />',
    '  <option name="LINE_SEPARATOR" value="&#10;" />',
    '  <option name="NO_SUCH_ROOT" value="1" />',
    '  <option name="FORMATTER_TAGS_ACCEPT_REGEXP" value="true" />',
    '  <option name="FORMATTER_OFF_TAG" value="fmt(?=off)" />',
    '  <option name="FORMATTER_ON_TAG" value="(?i)fmt:\\s*on" />',
    '  <LuaCodeStyleSettings>',
    '    <option name="SPACE_BEFORE_SEMICOLON" value="true" />',
    '    <option name="NO_SUCH_FIELD" value="true" />',
    '  </LuaCodeStyleSettings>',
    '  <codeStyleSettings language="Lua">',
    '    <option name="CALL_PARAMETERS_WRAP" value="5" />',
    '    <indentOptions><option name="INDENT_SIZE" value="99" /></indentOptions>',
    '  </codeStyleSettings>',
    '  <codeStyleSettings language="PHP" />',
  }))
  local report = assert(import({ path = path }))
  expect.equality(report.source, path)
  expect.equality(report.languages[1], {
    id = 'general',
    imported = {
      { key = 'hard_wrap_at', value = 100 },
      { key = 'markers.on', value = '\\cfmt:\\s*on' },
      { key = 'markers.regex', value = true },
    },
    left_out = { 'root:LINE_SEPARATOR' },
    unknown = { 'root:NO_SUCH_ROOT' },
    invalid = {},
    not_converted = {
      { part = 'root:FORMATTER_OFF_TAG', reason = 'cannot convert the Java regex "fmt(?=off)": cannot convert (?=' },
    },
  })
  local lua = language(report, 'lua')
  expect.equality(lua.imported, {})
  expect.equality(lua.left_out, { 'custom:SPACE_BEFORE_SEMICOLON' })
  expect.equality(lua.unknown, { 'custom:NO_SUCH_FIELD' })
  expect.equality(lua.invalid, {
    {
      key = 'indent.size',
      field = 'indent:INDENT_SIZE',
      value = '99',
      message = '99 is out of range 0–32',
    },
    {
      key = 'wrap.call_arguments',
      field = 'common:CALL_PARAMETERS_WRAP',
      value = '5',
      message = 'no choice for the PhpStorm value 5',
    },
  })
  expect.equality(
    vim.tbl_map(function(each)
      return each.id
    end, report.languages),
    { 'general', 'c', 'lua' }
  )
  expect.equality(language(report, 'c').invalid, {
    {
      key = 'embedded.lua_indent',
      field = 'lang:Lua:indent:INDENT_SIZE',
      value = '99',
      message = '99 is out of range 0–32',
    },
  })
  expect.equality(report.not_installed, { 'PHP' })
  expect.equality(report.totals, {
    imported = 3,
    left_out = 2,
    unknown = 2,
    invalid = 3,
    not_converted = 1,
    not_installed = 1,
  })
  expect.equality(child:notices(), {
    {
      level = H.levels.INFO,
      message = ('codestyle: imported %s into the Draft: 3 values, 2 left out, 2 unknown, 3 invalid (defaults used), 1 not converted, 1 not installed'):format(
        path
      ),
    },
  })
end

T['sources'] = MiniTest.new_set()

T['sources']['Project.xml is used when the repo has it, and the component is unwrapped'] = function()
  open_draft()
  write_xml(
    table.concat({
      '<component name="ProjectCodeStyleConfiguration">',
      scheme({ '  <option name="RIGHT_MARGIN" value="90" />' }),
      '</component>',
    }, '\n'),
    child.paths.repo .. '/.idea/codeStyles/Project.xml'
  )
  local other = write_xml(scheme({ '  <option name="RIGHT_MARGIN" value="70" />' }))
  local report = assert(import({ root = child.paths.repo, path = other }))
  local project = child.paths.repo .. '/.idea/codeStyles/Project.xml'
  expect.equality(report.source, project)
  expect.equality(stored(), { general = { hard_wrap_at = 90 } })
  -- The user is told once that the path they gave was not used.
  local warning = {
    level = H.levels.WARN,
    message = ('codestyle: %s was not imported: the repo has %s, which an import always uses'):format(other, project),
  }
  expect.equality(child:notices()[1], warning)
  import({ root = child.paths.repo, path = other })
  local warnings = vim.tbl_filter(function(notice)
    return notice.level == H.levels.WARN
  end, child:notices())
  expect.equality(warnings, { warning })
end

T['sources']['else the given path; codeStyleConfig.xml is never read'] = function()
  open_draft()
  write_xml(
    '<component name="ProjectCodeStyleConfiguration"><state><option name="USE_PER_PROJECT_SETTINGS" value="true" /></state></component>',
    child.paths.repo .. '/.idea/codeStyles/codeStyleConfig.xml'
  )
  local report, message = import({ root = child.paths.repo })
  expect.equality(report, nil)
  expect.equality(
    message,
    ('no Scheme XML to import: %s/.idea/codeStyles/Project.xml does not exist and no path was given'):format(
      child.paths.repo
    )
  )
  local path = write_xml(scheme({ '  <option name="RIGHT_MARGIN" value="70" />' }))
  report = assert(import({ root = child.paths.repo, path = path }))
  expect.equality(report.source, path)
  expect.equality(stored(), { general = { hard_wrap_at = 70 } })
end

return T
