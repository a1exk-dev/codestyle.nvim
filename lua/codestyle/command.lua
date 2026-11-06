-- The `:Codestyle` command (ADR-0014).

local M = {}

---@type table<string, fun(opts: vim.api.keyset.create_user_command.command_args)>
local subcommands = {
  format = function()
    require('codestyle').format({ buf = 0 })
  end,
}

---@param opts vim.api.keyset.create_user_command.command_args
function M.run(opts)
  local subcommand = subcommands[opts.fargs[1]]
  if not subcommand then
    vim.notify(('codestyle: unknown subcommand "%s"'):format(opts.fargs[1]), vim.log.levels.ERROR)
    return
  end
  subcommand(opts)
end

---@param arg_lead string
---@return string[]
function M.complete(arg_lead)
  local names = vim.tbl_keys(subcommands)
  table.sort(names)
  return vim.tbl_filter(function(name)
    return vim.startswith(name, arg_lead)
  end, names)
end

return M
