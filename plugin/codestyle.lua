if vim.g.loaded_codestyle then
  return
end
vim.g.loaded_codestyle = true

vim.api.nvim_create_user_command('Codestyle', function(opts)
  require('codestyle.command').run(opts)
end, {
  nargs = 1,
  desc = 'codestyle.nvim: format the buffer',
  complete = function(arg_lead)
    return require('codestyle.command').complete(arg_lead)
  end,
})
