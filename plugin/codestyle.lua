if vim.g.loaded_codestyle then
  return
end
vim.g.loaded_codestyle = true

vim.api.nvim_create_user_command('Codestyle', function(opts)
  require('codestyle.command').run(opts)
end, {
  nargs = '*',
  range = true,
  desc = 'codestyle.nvim: open the Menu, format or rearrange the buffer or the range, or import a Scheme XML',
  complete = function(arg_lead, cmd_line)
    return require('codestyle.command').complete(arg_lead, cmd_line)
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

--- Adds the conform formatter once conform's plugin is loaded. Without
--- lazy.nvim a config may require conform's module only on a later event
--- (the first save), so the module is required here.
local function register_conform()
  if pcall(require, 'conform') then
    require('codestyle.instance').get().conform.register()
  end
end

-- A conform that loads after startup without lazy.nvim (`:packadd`): its
-- plugin file is sourced when it loads.
vim.api.nvim_create_autocmd('SourcePost', {
  group = group,
  pattern = '*/plugin/conform.lua',
  desc = 'codestyle.nvim: add the conform formatter when conform loads',
  callback = register_conform,
})

-- The default key waits for the end of startup, so that the user's
-- `mapleader`, own mappings and `setup{ keys = false }` come first. A conform
-- that the user's config loaded by then, or whose plugin is on the
-- runtimepath, gets the formatter too.
local function after_startup()
  require('codestyle.instance').get().keys.apply()
  if package.loaded.conform or #vim.api.nvim_get_runtime_file('plugin/conform.lua', false) > 0 then
    register_conform()
  end
end
if vim.v.vim_did_enter == 1 then
  vim.schedule(after_startup)
else
  vim.api.nvim_create_autocmd('VimEnter', { once = true, callback = after_startup })
end
