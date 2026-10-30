-- PROTOTYPE (throwaway): merge of host and embedded-language block trees.
--   nvim --headless -l prototype/merge/run.lua                 golden check of every case
--   nvim --headless -l prototype/merge/run.lua show <file> [lang.option=value ...]
--                                                              merged tree, gap owners and indent owners
local here = debug.getinfo(1, 'S').source:sub(2):match('(.*/)') or './'
package.path = here .. 'lua/?.lua;' .. here .. 'lua/?/init.lua;' .. package.path

local corpus = vim.fs.normalize(os.getenv('CODESTYLE_CORPUS') or '~/Projects/phpstorm-editorconfig')
local parsers = os.getenv('CODESTYLE_PARSERS')

-- Injection queries come from nvim-treesitter. In a --clean run, look for it where lazy.nvim puts it.
local nts = vim.fs.normalize('~/.local/share/nvim/lazy/nvim-treesitter/runtime')
if vim.uv.fs_stat(nts) then vim.opt.rtp:prepend(nts) end
for _, lang in ipairs({ 'php', 'php_only', 'twig', 'html' }) do
  local ok, added = pcall(vim.treesitter.language.add, lang)
  if not (ok and added) and parsers then pcall(vim.treesitter.language.add, lang, { path = parsers .. '/' .. lang .. '.so' }) end
  if not pcall(vim.treesitter.language.inspect, lang) then
    io.stderr:write(('missing Tree-sitter parser: %s (install it, or set CODESTYLE_PARSERS to a directory with %s.so)\n'):format(lang, lang))
    os.exit(1)
  end
end

local Proto = require('merge_proto')
local B = require('merge_proto.blocks')

local function read(path)
  local f = assert(io.open(path, 'rb'))
  local s = f:read('a')
  f:close()
  return s
end

local function strip_indent(s)
  return (s:gsub('\n[ \t]+', '\n'):gsub('^[ \t]+', ''))
end

local function pos(src, byte)
  local before = src:sub(1, byte)
  local line = select(2, before:gsub('\n', '')) + 1
  local col = #before - (before:match('.*()\n') or 0)
  return line .. ':' .. col
end

local function label(b)
  local t = b.type
  if b.tag and b.lang == 'html' then t = t .. '<' .. b.tag .. '>' end
  if b.tag and b.lang == 'twig' then t = t .. '{' .. b.tag .. '}' end
  return b.lang .. ':' .. t
end

-- Golden cases from the Behaviour Records -------------------------------------------------------------

-- Record base settings → our option keys (`common:` means the record's own language).
local function base_settings(record_lang, base)
  local out = {}
  for k, v in pairs(base) do
    local val = (v == 'true') or (v ~= 'false' and (tonumber(v) or v))
    if v == 'false' then val = false end
    local lang, opt = k:match('^lang:(%w+):INDENT%.(.+)$')
    lang = lang and lang:lower()
    if not lang then
      opt = k:match('^common:INDENT%.(.+)$')
      lang = record_lang
    end
    if not opt then return nil end -- a base this toy does not model (alignments)
    local map = { USE_TAB_CHARACTER = 'use_tab', INDENT_SIZE = 'indent_size', CONTINUATION_INDENT_SIZE = 'continuation_indent_size', TAB_SIZE = 'tab_size' }
    if not map[opt] then return nil end
    out[lang .. '.' .. map[opt]] = val
  end
  return out
end

local function option_setting(record_lang, key, value)
  local html = key:match('^html%.(.+)$')
  local lang = html and 'html' or record_lang
  key = html or key
  if key == 'indent_size' then return lang .. '.indent_size', tonumber(value) end
  if key == 'indent_style' then return lang .. '.use_tab', value == 'tab' end
  if key == 'ij_php_indent_code_in_php_tags' then return 'php.indent_code_in_php_tags', value == 'true' end
end

local function cases()
  local list, seen = {}, {}
  local specs = {
    { 'php', 'ij_php_indent_code_in_php_tags', { 'html_template.php', 'r2_html_template.php', 'r2_php_first_then_html.php' } },
    { 'php', 'indent_size', { 'html_template.php', 'r2_html_template.php', 'r2_php_first_then_html.php' } },
    { 'php', 'indent_style', { 'html_template.php', 'r2_html_template.php', 'r2_php_first_then_html.php' } },
    { 'twig', 'indent_size', { 'indent.twig', 'nesting.twig', 'empty_lines.twig', 'attr_breaks.twig', 'attributes.twig' } },
    { 'twig', 'indent_style', { 'indent.twig', 'nesting.twig', 'empty_lines.twig', 'attr_breaks.twig', 'attributes.twig' } },
  }
  for _, spec in ipairs(specs) do
    local lang, key, files = spec[1], spec[2], spec[3]
    local rec = vim.json.decode(read(('%s/data/behavior/%s/%s.json'):format(corpus, lang, key)))
    local function add(base, settings, value_label)
      for _, f in ipairs(files) do
        local expected = settings.__changed and settings.__changed[f] and settings.__changed[f].output or rec.base_outputs[base][f]
        local s = vim.deepcopy(settings)
        s.__changed = nil
        local name = ('%s %-27s %s'):format(lang, f, value_label)
        local key = lang .. f .. vim.inspect(s)
        if expected and not seen[key] then
          seen[key] = true
          list[#list + 1] = { name = name, host = lang, settings = s, expected = expected }
        end
      end
    end
    for base in pairs(rec.base_outputs) do
      local bs = base_settings(lang, (function()
        for _, r in ipairs(rec.results) do if r.base == base then return r.base_settings end end
        return {}
      end)())
      if bs then add(base, bs, ('[%s]'):format(base)) end
    end
    for _, r in ipairs(rec.results) do
      local bs = base_settings(lang, r.base_settings)
      local k, v = option_setting(lang, key, r.value)
      if bs and k then
        bs[k] = v
        bs.__changed = r.changed_files
        add(r.base, bs, ('[%s] %s=%s'):format(r.base, key, r.value))
      end
    end
  end
  table.sort(list, function(a, b) return a.name < b.name end)
  return list
end

-- Mismatches that are not about the merge. Each is printed as KNOWN with its reason.
local KNOWN = {
  {
    match = '^twig attributes%.twig .*tab',
    why = 'PhpStorm wrapped these attribute lines itself (right margin). A line break that the formatter adds aligns with the '
      .. "tag's tabs plus spaces; a line break from the input is all tabs (attr_breaks.twig). The stripped golden output cannot "
      .. 'tell the two apart. An engine question, not a merge question.',
  },
}

local function check()
  local pass, total, known = 0, 0, 0
  for _, c in ipairs(cases()) do
    local input = strip_indent(c.expected)
    local ok, out = pcall(Proto.format, input, c.host, c.settings)
    total = total + 1
    local why
    for _, k in ipairs(KNOWN) do
      if c.name:match(k.match) then why = k.why end
    end
    if ok and out == c.expected then
      pass = pass + 1
      print('PASS  ' .. c.name)
    elseif ok and why then
      known = known + 1
      print('KNOWN ' .. c.name .. '\n      ' .. why)
    else
      print('FAIL  ' .. c.name)
      if ok then
        print(vim.text.diff(c.expected, out, { ctxlen = 1 }))
      else
        print('  ' .. tostring(out))
      end
    end
  end
  print(('\n%d of %d golden cases match PhpStorm, %d known mismatches (input: the golden output with every indent removed)'):format(pass, total, known))
end

-- show: the merged tree and who owns each gap ---------------------------------------------------------

local function show(path, extra)
  local host = path:match('%.php$') and 'php' or path:match('%.twig$') and 'twig' or (path:find('/PHP/') and 'php') or 'twig'
  local settings = {}
  for _, kv in ipairs(extra) do
    local k, v = kv:match('^(.-)=(.*)$')
    settings[k] = v == 'true' or (v ~= 'false' and (tonumber(v) or v))
    if v == 'false' then settings[k] = false end
  end
  local src = read(path)
  local out, r = Proto.format(src, host, settings)
  local times = {}
  for i = 1, 21 do
    local t0 = vim.uv.hrtime()
    Proto.format(src, host, settings)
    times[i] = (vim.uv.hrtime() - t0) / 1e6
  end
  table.sort(times)

  print(('== %s (host: %s, indent Options from: %s)'):format(path, host, r.indent_options_from))
  print('\n-- merged block tree (‹lang› marks a child whose language differs from its parent; * synthetic, ro read-only)')
  local function dump(b, depth)
    local text = src:sub(b.s + 1, math.min(b.e, b.s + 28)):gsub('\n', '⏎')
    local cross = b.parent and b.parent.lang ~= b.lang and (' ‹' .. b.lang .. '›') or ''
    local flags = (b.synthetic and ' *' or '') .. (b.readonly and ' ro' or '')
    print(('%s%s%s%s  [%s-%s]  %s'):format(string.rep('  ', depth), label(b), flags, cross, pos(src, b.s), pos(src, b.e), text))
    if b.children and not b.readonly and not (B.is_leaf(b)) then
      for _, c in ipairs(b.children) do
        if not B.is_leaf(c) or depth < 99 then dump(c, depth + 1) end
      end
    end
  end
  dump(r.root, 0)

  print('\n-- host blocks dissolved because they cross a markup block')
  if #r.dissolved == 0 then print('   none') end
  for _, d in ipairs(r.dissolved) do
    print(('   %s [%s-%s] crosses %s [%s-%s]'):format(label(d.block), pos(src, d.block.s), pos(src, d.block.e), label(d.crossed), pos(src, d.crossed.s), pos(src, d.crossed.e)))
  end

  print('\n-- line starts: the block that starts the line, its parent, and the indent kind the parent\'s plugin chose')
  for _, l in ipairs(r.info.lines) do
    local kind = type(l.kind) == 'table' and ('align to ' .. label(l.kind.align)) or l.kind
    print(('   %-6s %-34s child of %-30s → %-14s col %d'):format(pos(src, l.leaf.s), label(l.block), label(l.parent), kind, l.col))
  end

  print('\n-- gap owners (the lowest block that holds both leaves decides Spacing), by owner and leaf languages')
  local counts = {}
  for _, g in ipairs(r.info.gaps) do
    local k = ('%-5s owns gaps %s → %s'):format(g.owner.lang, g.left.lang, g.right.lang)
    counts[k] = (counts[k] or 0) + 1
  end
  local keys = vim.tbl_keys(counts)
  table.sort(keys)
  for _, k in ipairs(keys) do print(('   %4d  %s'):format(counts[k], k)) end
  print('   mixed gaps in detail:')
  for _, g in ipairs(r.info.gaps) do
    if g.left.lang ~= g.right.lang or g.owner.lang ~= g.left.lang then
      print(('     %-6s %-22s | %-22s owner %s'):format(pos(src, g.right.s), label(g.left), label(g.right), label(g.owner)))
    end
  end

  print(('\n-- time: parse + build + merge + indent pass, median of 21 runs: %.2f ms'):format(times[11]))
  print('\n-- result')
  io.write(out)
end

if arg[1] == 'show' then
  show(arg[2], { unpack(arg, 3) })
else
  check()
end
