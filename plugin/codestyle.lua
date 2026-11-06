if vim.g.loaded_codestyle then
  return
end
vim.g.loaded_codestyle = true

vim.api.nvim_create_user_command('Codestyle', function(opts)
  require('codestyle.command').run(opts)
end, {
  nargs = '?',
  range = true,
  desc = 'codestyle.nvim: open the Menu, or format or rearrange the buffer or the range',
  complete = function(arg_lead)
    return require('codestyle.command').complete(arg_lead)
  end,
})

vim.keymap.set('n', '<Plug>(codestyle-format)', function()
  require('codestyle').format({ buf = 0 })
end, { desc = 'codestyle.nvim: format the buffer' })
vim.keymap.set('x', '<Plug>(codestyle-format)', function()
  require('codestyle.instance').get().format_selection()
end, { desc = 'codestyle.nvim: format the selected lines' })

local group = vim.api.nvim_create_augroup('codestyle', {})
vim.api.nvim_create_autocmd('FileType', {
  group = group,
  desc = 'codestyle.nvim: set formatexpr on claimed buffers',
  callback = function(args)
    require('codestyle.instance').get().formatexpr.on_filetype(args.buf)
  end,
})

vim.api.nvim_create_autocmd('User', {
  group = group,
  pattern = 'LazyLoad',
  desc = 'codestyle.nvim: add the conform formatter when lazy.nvim loads conform',
  callback = function(args)
    if args.data == 'conform.nvim' then
      require('codestyle.instance').get().conform.register()
    end
  end,
})

-- The default key waits for the end of startup, so that the user's
-- `mapleader`, own mappings and `setup{ keys = false }` come first. A conform
-- that the user's config loaded by then gets the formatter too.
local function after_startup()
  local instance = require('codestyle.instance').get()
  instance.keys.apply()
  instance.conform.register()
end
if vim.v.vim_did_enter == 1 then
  vim.schedule(after_startup)
else
  vim.api.nvim_create_autocmd('VimEnter', { once = true, callback = after_startup })
end
