-- PROTOTYPE (throwaway): parse → build blocks per Language Plugin → merge → indent pass.
local B = require('merge_proto.blocks')
local Merge = require('merge_proto.merge')
local Indent = require('merge_proto.indent')

local M = {}

M.plugins = {
  php = require('merge_proto.plugins.php'),
  html = require('merge_proto.plugins.html'),
  twig = require('merge_proto.plugins.twig'),
}

-- Defaults from the Research Corpus (PhpStorm 2026.2.3 Default scheme), only the Options this toy reads.
M.defaults = {
  php = { indent_size = 4, continuation_indent_size = 4, use_tab = false, tab_size = 4, indent_code_in_php_tags = false },
  html = {
    indent_size = 4, continuation_indent_size = 8, use_tab = false, tab_size = 4, align_attributes = true,
    do_not_indent_children_of = { 'html', 'body', 'thead', 'tbody', 'tfoot' },
  },
  twig = { indent_size = 4, continuation_indent_size = 8, use_tab = false, tab_size = 4 },
}

function M.styles(settings)
  local styles = vim.deepcopy(M.defaults)
  for key, value in pairs(settings or {}) do
    local lang, opt = key:match('^(%w+)%.(.+)$')
    styles[lang][opt] = value
  end
  return styles
end

--- @return string formatted, table report
function M.format(src, host, settings)
  local styles = M.styles(settings)
  local parser = vim.treesitter.get_string_parser(src, host)
  parser:parse(true)
  local host_tree = parser:trees()[1]
  local host_root = M.plugins[host].build(host_tree:root(), src)

  local markup_root, included
  local child = parser:children().html
  if child then
    local tree = child:trees()[1]
    if tree then
      included = tree:included_ranges(true)
      markup_root = M.plugins.html.build(tree:root(), src, included)
    end
  end

  local merged, log = Merge.merge(host_root, markup_root)
  Merge.set_parents(merged, nil)
  local io_lang = M.plugins[host].indent_options(markup_root ~= nil)
  local text, info = Indent.run({ src = src, root = merged, plugins = M.plugins, styles = styles, io = styles[io_lang] })
  return text, { root = merged, dissolved = log, info = info, indent_options_from = io_lang, src = src }
end

return M
