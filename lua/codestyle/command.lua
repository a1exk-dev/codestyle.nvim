-- The `:Codestyle` command (ADR-0014). With no argument it opens the Menu
-- (#50 New decisions). `arrange` always rearranges (ADR-0011). `import [path]`
-- opens the Menu and imports a Scheme XML there (ADR-0010).

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
  if opts.fargs[1] == 'import' then
    -- The rest of the line is the path, blanks included (ADR-0010).
    local path = vim.trim(opts.args:gsub('^%s*import', '', 1))
    require('codestyle.instance').get().menu.open({ import = path ~= '' and path or true })
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
---@param cmd_line? string
---@return string[]
function M.complete(arg_lead, cmd_line)
  if cmd_line and cmd_line:match('^%S+%s+import%s') then
    return vim.fn.getcompletion(arg_lead, 'file')
  end
  local names = vim.list_extend(vim.tbl_keys(subcommands), { 'import' })
  table.sort(names)
  return vim.tbl_filter(function(name)
    return vim.startswith(name, arg_lead)
  end, names)
end

return M
