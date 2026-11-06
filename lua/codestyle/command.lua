-- The `:Codestyle` command (ADR-0014). With no argument it opens the Menu
-- (#50 New decisions). `arrange` always rearranges (ADR-0011).

local M = {}

---@type table<string, fun(opts: vim.api.keyset.create_user_command.command_args)>
local subcommands = {
  format = function(opts)
    require('codestyle').format({ buf = 0, range = opts.range > 0 and { opts.line1, opts.line2 } or nil })
  end,
  -- Rearranges also when "Rearrange when formatting" is off, then formats (ADR-0011).
  arrange = function(opts)
    require('codestyle').format({
      buf = 0,
      range = opts.range > 0 and { opts.line1, opts.line2 } or nil,
      arrangement = 'force',
    })
  end,
}

---@param opts vim.api.keyset.create_user_command.command_args
function M.run(opts)
  if not opts.fargs[1] then
    require('codestyle.instance').get().menu.open()
    return
  end
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
