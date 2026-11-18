-- The package spec that lazy.nvim reads from a plugin's root (codestyle-home#14):
-- a user whose spec leaves snacks.nvim out still gets it in the same startup.
-- The Language Plugins ship no lazy.lua.
return {
  { 'folke/snacks.nvim' },
}
