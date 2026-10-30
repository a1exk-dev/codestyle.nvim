-- PROTOTYPE (throwaway): `nvim -c 'source prototype/menu/init.lua'`, or `:source` it in a running Neovim.
-- Opens the Menu prototype. ]v / [v switch between the three variants; q closes; :CodestyleProto reopens.
local dir = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h")
vim.opt.rtp:prepend(dir)
for name in pairs(package.loaded) do
  if name:match("^codestyle_proto") then
    package.loaded[name] = nil
  end
end
local function open()
  require("codestyle_proto").open(tonumber(vim.g.codestyle_proto_variant) or 1)
end
-- With `nvim -c`, wait until startup ends, so a start screen (e.g. LazyVim's dashboard) cannot take the focus.
if vim.v.vim_did_enter == 1 then
  open()
else
  vim.api.nvim_create_autocmd("VimEnter", {
    once = true,
    callback = function()
      vim.defer_fn(open, 200)
    end,
  })
end
