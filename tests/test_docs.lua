-- The docs check (codestyle-home#64): `:help codestyle` is the full user
-- reference, so it names every command, subcommand, `<Plug>` map, default key
-- and `setup{}` field that the running Core registers, and nothing that it
-- does not register. The README is a short front page: it may leave names out,
-- but it names nothing that the Core does not register (codestyle-home#63).
--
-- How the help and the README name each kind:
--   command      `:Codestyle` (also after a range, as `:[range]Codestyle`)
--   subcommand   `:Codestyle format`, or the tag `*:Codestyle-format*`
--   <Plug> map   `<Plug>(codestyle-format)`
--   default key  `<leader>cf`
--   setup field  the tag `*codestyle-setup-keys*`, or a top-level key of a
--                `setup{ ... }` or `setup({ ... })` table in the text

local H = dofile('tests/helpers.lua')
local expect = MiniTest.expect

local help_file = 'doc/codestyle.txt'
local readme_file = 'README.md'

local child = H.new_child()

local T = MiniTest.new_set({
  hooks = {
    pre_case = function()
      child:setup()
    end,
    post_case = function()
      child:teardown()
    end,
  },
})

---@alias codestyle.test.DocKind 'command'|'subcommand'|'plug'|'key'|'setup'

--- The kinds in the order that problems are listed.
---@type codestyle.test.DocKind[]
local kinds = { 'command', 'subcommand', 'plug', 'key', 'setup' }

---@param path string
---@return string
local function read(path)
  local file = assert(io.open(path, 'r'))
  local text = file:read('*a')
  file:close()
  return text
end

--- The top-level keys of each `setup{ ... }` or `setup({ ... })` table in the
--- text. Nested tables are skipped, so `filetypes = { xml = false }` gives
--- only `filetypes`. The `setup` of another module, such as
--- `require('conform').setup({ ... })`, is not the Core's and is skipped.
---@param text string
---@return string[]
local function setup_table_keys(text)
  local keys = {}
  local init = 1
  while true do
    local start, open = text:find('setup%s*%(?%s*{', init)
    if not open then
      break
    end
    local module = text:sub(1, start - 1):match('require%s*%(?%s*[\'"]([^\'"]+)[\'"]%s*%)?%.$')
    local depth, top = 1, {}
    local pos = open + 1
    while pos <= #text and depth > 0 do
      local char = text:sub(pos, pos)
      if char == '{' then
        depth = depth + 1
      elseif char == '}' then
        depth = depth - 1
      elseif depth == 1 then
        table.insert(top, char)
      end
      pos = pos + 1
    end
    if not module or module == 'codestyle' then
      for key in table.concat(top):gmatch('([%a_][%w_]*)%s*=[^=]') do
        table.insert(keys, key)
      end
    end
    init = pos
  end
  return keys
end

--- What a help text names, by kind.
---@param text string
---@return table<codestyle.test.DocKind, table<string, true>>
local function named(text)
  local found = { command = {}, subcommand = {}, plug = {}, key = {}, setup = {} }
  for name in text:gmatch('[:%]](Codestyle%w*)') do
    found.command[name] = true
  end
  for name in text:gmatch('[:%]]Codestyle (%l+)') do
    found.subcommand[name] = true
  end
  for name in text:gmatch('%*:Codestyle%-(%l+)%*') do
    found.subcommand[name] = true
  end
  for name in text:gmatch('<Plug>%(codestyle[^)]*%)') do
    found.plug[name] = true
  end
  for name in text:gmatch('<[Ll]eader>%w+') do
    found.key['<leader>' .. name:sub(9)] = true
  end
  for name in text:gmatch('%*codestyle%-setup%-([%w_]+)%*') do
    found.setup[name] = true
  end
  for _, name in ipairs(setup_table_keys(text)) do
    found.setup[name] = true
  end
  return found
end

--- The names of each kind that a text names and the Core does not register.
---@param registered table<codestyle.test.DocKind, string[]>
---@param found table<codestyle.test.DocKind, table<string, true>>
---@param doc string the name of the text in each problem
---@return string[]
local function unregistered(registered, found, doc)
  local problems = {}
  for _, kind in ipairs(kinds) do
    local known = {}
    for _, name in ipairs(registered[kind]) do
      known[name] = true
    end
    local extra = vim.tbl_keys(found[kind])
    table.sort(extra)
    for _, name in ipairs(extra) do
      if not known[name] then
        table.insert(problems, ('%s %s is in the %s but not registered'):format(kind, name, doc))
      end
    end
  end
  return problems
end

--- The docs check: what the Core registers and the help does not name, then
--- what the help names and the Core does not register.
---@param registered table<codestyle.test.DocKind, string[]>
---@param text string the help text
---@return string[] # the problems, empty when the help agrees with the Core
local function check(registered, text)
  local found = named(text)
  local problems = {}
  for _, kind in ipairs(kinds) do
    for _, name in ipairs(registered[kind]) do
      if not found[kind][name] then
        table.insert(problems, ('%s %s is not in the help'):format(kind, name))
      end
    end
  end
  return vim.list_extend(problems, unregistered(registered, found, 'help'))
end

--- The docs check of the README (codestyle-home#63): the README is a short
--- front page, so it may leave names out, but it names nothing that the Core
--- does not register.
---@param registered table<codestyle.test.DocKind, string[]>
---@param text string the README text
---@return string[] # the problems, empty when the README agrees with the Core
local function readme_check(registered, text)
  return unregistered(registered, named(text), 'README')
end

--- What the running Core in the child registers, read from Neovim itself and
--- from the Core's list of `setup{}` fields.
---@return table<codestyle.test.DocKind, string[]>
local function registered()
  return child.lua([[
    local result = { command = {}, subcommand = {}, plug = {}, key = {} }
    for name in pairs(vim.api.nvim_get_commands({})) do
      if name:find('^Codestyle') then
        table.insert(result.command, name)
      end
    end
    result.subcommand = vim.fn.getcompletion('Codestyle ', 'cmdline')
    local plugs, keys = {}, {}
    for _, mode in ipairs({ 'n', 'x', 's', 'o', 'i', 'c', 't' }) do
      for _, map in ipairs(vim.api.nvim_get_keymap(mode)) do
        if map.lhs:find('^<Plug>%(codestyle') then
          plugs[map.lhs] = true
        elseif (map.rhs or ''):find('^<Plug>%(codestyle') then
          -- The child keeps the default mapleader, a backslash.
          keys[(map.lhs:gsub('^\\', '<leader>'))] = true
        end
      end
    end
    result.plug = vim.tbl_keys(plugs)
    result.key = vim.tbl_keys(keys)
    result.setup = require('codestyle.setup').fields
    return result
  ]])
end

T[':helptags'] = MiniTest.new_set()

T[':helptags']['builds the tags of the help folder with no error'] = function()
  local dir = child.paths.root .. '/docs'
  vim.fn.mkdir(dir .. '/doc', 'p')
  vim.fn.writefile(vim.fn.readfile(help_file), dir .. '/doc/codestyle.txt')

  -- A duplicate tag makes `:helptags` fail with E154.
  local ok, err = pcall(child.cmd, 'helptags ' .. dir .. '/doc')

  expect.equality({ ok, ok or err }, { true, true })
end

T[':helptags'][':help opens the section of each tag'] = function()
  local dir = child.paths.root .. '/docs'
  vim.fn.mkdir(dir .. '/doc', 'p')
  vim.fn.writefile(vim.fn.readfile(help_file), dir .. '/doc/codestyle.txt')
  child.cmd('helptags ' .. dir .. '/doc')
  child.lua('vim.opt.runtimepath:prepend(...)', { dir })

  for _, tag in ipairs({ 'codestyle', 'codestyle-conform', 'codestyle-health' }) do
    child.cmd('help ' .. tag)
    expect.equality(child.api.nvim_get_current_line():find('*' .. tag .. '*', 1, true) ~= nil, true)
    child.cmd('close')
  end
end

T['the help file ends with the help modeline'] = function()
  local lines = vim.fn.readfile(help_file)

  expect.equality(lines[#lines], ' vim:tw=78:ts=8:ft=help:norl:')
end

T['the help names what the Core registers, and nothing else'] = function()
  expect.equality(check(registered(), read(help_file)), {})
end

T['the README names nothing that the Core does not register'] = function()
  expect.equality(readme_check(registered(), read(readme_file)), {})
end

T['the setup{} field list names the fields of the codestyle.Setup class, in order'] = function()
  local annotated, in_class = {}, false
  for _, line in ipairs(vim.split(read('lua/codestyle/setup.lua'), '\n')) do
    if line:match('^%-%-%-@class ') then
      in_class = line == '---@class codestyle.Setup'
    elseif in_class and not line:match('^%-%-%-') then
      in_class = false
    elseif in_class then
      table.insert(annotated, line:match('^%-%-%-@field ([%w_]+)'))
    end
  end

  expect.equality(child.lua_get("require('codestyle.setup').fields"), annotated)
end

T['the docs check'] = MiniTest.new_set()

T['the docs check']['finds a registered name that the help leaves out'] = function()
  local core = {
    command = { 'Codestyle' },
    subcommand = { 'format', 'arrange' },
    plug = { '<Plug>(codestyle-format)', '<Plug>(codestyle-menu)' },
    key = { '<leader>cf' },
    setup = { 'filetypes', 'keys' },
  }
  local text = table.concat({
    '*:Codestyle*  `:Codestyle format`',
    '<Plug>(codestyle-format) is mapped to <leader>cf.',
    '>lua',
    "  require('codestyle').setup({ filetypes = { xml = false } })",
    "  require('conform').setup({ formatters_by_ft = { ['*'] = { 'codestyle' } } })",
    '<',
  }, '\n')

  expect.equality(check(core, text), {
    'subcommand arrange is not in the help',
    'plug <Plug>(codestyle-menu) is not in the help',
    'setup keys is not in the help',
  })
end

T['the docs check']['finds a name in the help that the Core does not register'] = function()
  local core = {
    command = { 'Codestyle' },
    subcommand = { 'format' },
    plug = { '<Plug>(codestyle-format)' },
    key = { '<leader>cf' },
    setup = { 'keys' },
  }
  local text = table.concat({
    '`:Codestyle format` and `:[range]Codestyle sort`, or :CodestyleInfo',
    '*:Codestyle-lint*',
    '<Plug>(codestyle-format) and <Plug>(codestyle-sort) on <leader>cf and <Leader>cs',
    '*codestyle-setup-keys*  `setup{ keys = false, theme = { dark = true } }`',
  }, '\n')

  expect.equality(check(core, text), {
    'command CodestyleInfo is in the help but not registered',
    'subcommand lint is in the help but not registered',
    'subcommand sort is in the help but not registered',
    'plug <Plug>(codestyle-sort) is in the help but not registered',
    'key <leader>cs is in the help but not registered',
    'setup theme is in the help but not registered',
  })
end

T['the docs check']['finds a name in the README that the Core does not register'] = function()
  local core = {
    command = { 'Codestyle' },
    subcommand = { 'format', 'import' },
    plug = { '<Plug>(codestyle-format)', '<Plug>(codestyle-menu)' },
    key = { '<leader>cf' },
    setup = { 'filetypes', 'keys' },
  }
  local text = table.concat({
    'Open the Menu with `:Codestyle`, or format with `:Codestyle fmt`.',
    'Map <Plug>(codestyle-open) to <leader>co.',
    '```lua',
    "require('codestyle').setup({ keys = false, style = 'psr12' })",
    "require('conform').setup({ formatters_by_ft = { ['*'] = { 'codestyle' } } })",
    '```',
  }, '\n')

  -- The README is a short front page: it may leave registered names out.
  expect.equality(readme_check(core, text), {
    'subcommand fmt is in the README but not registered',
    'plug <Plug>(codestyle-open) is in the README but not registered',
    'key <leader>co is in the README but not registered',
    'setup style is in the README but not registered',
  })
end

return T
